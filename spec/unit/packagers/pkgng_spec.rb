require 'spec_helper'

module Omnibus
  describe Packager::PKGNG do
    let(:project) do
      Project.new.tap do |project|
        project.name('project')
        project.homepage('https://example.com')
        project.install_dir('/opt/project')
        project.build_version('1.2.3')
        project.build_iteration('2')
        project.maintainer('Chef Software')
      end
    end

    subject { described_class.new(project) }

    let(:project_root) { "#{tmp_path}/project/root" }
    let(:package_dir)  { "#{tmp_path}/package/dir" }
    let(:staging_dir)  { "#{tmp_path}/staging/dir" }

    before do
      Config.project_root(project_root)
      Config.package_dir(package_dir)

      allow(subject).to receive(:staging_dir).and_return(staging_dir)
      create_directory(staging_dir)
    end

    describe '#base_package_name' do
      it 'is a DSL method' do
        expect(subject).to have_exposed_method(:base_package_name)
      end

      it 'has a default value' do
        expect(subject.base_package_name).to eq(project.package_name)
      end

      it 'must be a string' do
        expect { subject.base_package_name(Object.new) }.to raise_error(InvalidValue)
      end
    end

    describe '#licenses' do
      it 'is a DSL method' do
        expect(subject).to have_exposed_method(:licenses)
      end

      it 'has a default value' do
        expect(subject.licenses).to eq(['unknown'])
      end

      it 'must be an Array' do
        expect { subject.licenses(Object.new) }.to raise_error(InvalidValue)
      end
    end
    
    describe '#licenselogic' do
      it 'is a DSL method' do
        expect(subject).to have_exposed_method(:licenselogic)
      end

      it 'has a default value' do
        expect(subject.licenselogic).to eq('single')
      end

      it 'must be a string' do
        expect { subject.licenses(Object.new) }.to raise_error(InvalidValue)
      end
    end

    describe '#origin' do
      it 'is a DSL method' do
        expect(subject).to have_exposed_method(:origin)
      end

      it 'has a default value' do
        expect(subject.origin).to eq("misc/#{subject.safe_base_package_name}")
      end

      it 'must be a string' do
        expect { subject.origin(Object.new) }.to raise_error(InvalidValue)
      end
    end

    describe '#comment' do
      it 'is a DSL method' do
        expect(subject).to have_exposed_method(:comment)
      end

      it 'has a default value' do
        expect(subject.comment).to eq("The #{subject.safe_base_package_name} package")
      end

      it 'must be a string' do
        expect { subject.comment(Object.new) }.to raise_error(InvalidValue)
      end
    end

    describe '#id' do
      it 'is :pkgng' do
        expect(subject.id).to eq(:pkgng)
      end
    end

    describe '#package_name' do
      before do
        stub_ohai(platform: 'freebsd', version: '10.0') do |data|
          data['kernel']['machine'] = 'amd64'
        end
      end
      it 'includes the name, version, and build iteration' do
        expect(subject.package_name).to eq('project-1.2.3_2-FreeBSD10-amd64.txz')
      end
    end
    
    describe '#generate_compact_manifest' do
      it 'returns a hash' do
        mf = subject.generate_compact_manifest
        expect(mf).to be_a(Hash)
      end
      
      it 'has the correct content' do
        mf = subject.generate_compact_manifest
        expect(mf).to include('prefix')
        expect(mf).to include('name')
        expect(mf).to include('version')
        expect(mf).to include('arch')
        expect(mf).to include('origin')
        expect(mf).to include('comment')
        expect(mf).to include('maintainer')
        expect(mf).to include('www')
        expect(mf).to include('desc')
        expect(mf).to include('licenselogic')
        expect(mf).to include('licenses')
      end
    end
    
    describe '#generate_manifest' do
      it 'returns a hash' do
        cmf = subject.generate_compact_manifest
        mf = subject.generate_manifest(cmf)
        expect(mf).to be_a(Hash)
      end
      
      it 'has the correct content' do
        cmf = subject.generate_compact_manifest
        mf = subject.generate_manifest(cmf)
        expect(mf).to be_a(Hash)
        expect(mf).to include('files')
        expect(mf).to include('directories')
        expect(mf).to include('flatsize')
      end
    end
    
    describe '#enject_scripts' do
      before do
        create_file("#{project_root}/package-scripts/project/preinst") { "preinst" }
        create_file("#{project_root}/package-scripts/project/postinst") { "postinst" }
        create_file("#{project_root}/package-scripts/project/prerm") { "prerm" }
        create_file("#{project_root}/package-scripts/project/postrm") { "postrm" }
      end
      
      it 'returns a hash' do
        h = {}
        subject.inject_scripts(h)
        expect(h).to be_a(Hash)
      end
      
      it 'has the correct content' do
        h = {}
        subject.inject_scripts(h)
        expect(h).to include('scripts')
      end
    end
    
    describe '#write_manifest' do
      
      it 'generates the compact manifest' do
        cmf = subject.generate_compact_manifest
        subject.write_manifest(cmf, '+COMPACT_MANIFEST')
        expect("#{staging_dir}/+COMPACT_MANIFEST").to be_a_file
      end
      
      it 'has the content for the compact manifest' do
        cmf = subject.generate_compact_manifest
        subject.write_manifest(cmf, '+COMPACT_MANIFEST')
        raw_content = File.read("#{staging_dir}/+COMPACT_MANIFEST")
        
        content = JSON.parse(raw_content)
        expect(content).to include('prefix')
        expect(content).to include('name')
        expect(content).to include('version')
        expect(content).to include('arch')
        expect(content).to include('origin')
        expect(content).to include('comment')
        expect(content).to include('maintainer')
        expect(content).to include('www')
        expect(content).to include('desc')
        expect(content).to include('licenselogic')
        expect(content).to include('licenses')
      end
      
      it 'generates the manifest' do
        cmf = subject.generate_compact_manifest
        mf = subject.generate_manifest(cmf)
        subject.write_manifest(mf, '+MANIFEST')
        expect("#{staging_dir}/+MANIFEST").to be_a_file
      end
      
      it 'has the content for the manifest' do
        cmf = subject.generate_compact_manifest
        mf = subject.generate_manifest(cmf)
        subject.write_manifest(mf, '+MANIFEST')
        raw_content = File.read("#{staging_dir}/+MANIFEST")
        
        content = JSON.parse(raw_content)
        expect(content).to include('prefix')
        expect(content).to include('name')
        expect(content).to include('version')
        expect(content).to include('arch')
        expect(content).to include('origin')
        expect(content).to include('comment')
        expect(content).to include('maintainer')
        expect(content).to include('www')
        expect(content).to include('desc')
        expect(content).to include('licenselogic')
        expect(content).to include('licenses')
        expect(content).to include('files')
        expect(content).to include('flatsize')
        expect(content).to include('directories')
        
      end
      
    end

    describe '#create_package' do
      before do
        allow(subject).to receive(:shellout!)
        allow(Dir).to receive(:chdir) { |_, &b| b.call }
      end

      it 'logs a message' do
        output = capture_logging { subject.create_package }
        expect(output).to include('Creating package')
      end

      it 'uses the correct command' do
        expect(subject).to receive(:shellout!)
          .with(/pkg.create\ /)
        subject.create_package
      end
    end

    describe '#safe_base_package_name' do
      context 'when the project name is "safe"' do
        it 'returns the value without logging a message' do
          expect(subject.safe_base_package_name).to eq('project')
          expect(subject).to_not receive(:log)
        end
      end

      context 'when the project name has invalid characters' do
        before { project.name("Pro$ject123.for-realz_2") }

        it 'returns the value while logging a message' do
          output = capture_logging do
            expect(subject.safe_base_package_name).to eq('pro-ject123.for-realz-2')
          end

          expect(output).to include("The `name' component of FreeBSD package names can only include")
        end
      end
    end

    describe '#safe_build_iteration' do
      it 'returns the build iteration' do
        expect(subject.safe_build_iteration).to eq(project.build_iteration)
      end
    end

    describe '#safe_version' do
      context 'when the project build_version is "safe"' do
        it 'returns the value without logging a message' do
          expect(subject.safe_version).to eq('1.2.3_2')
          expect(subject).to_not receive(:log)
        end
        
        it 'returns the value containing the build iteration' do
          v = subject.safe_version
          iter = v.split('_').last
          expect(iter).to eq('2')
          expect(subject).to_not receive(:log)
        end
      end

      context 'when the project build_version has dashes' do
        before { project.build_version('1.2-rc.1') }

        it 'returns the value' do
          output = capture_logging do
            expect(subject.safe_version).to eq('1.2-rc.1_2')
          end
        end
      end

      context 'when the project build_version has invalid characters' do
        before { project.build_version("1.2$alpha.~##__2") }

        it 'returns the value while logging a message' do
          output = capture_logging do
            expect(subject.safe_version).to eq('1.2_alpha._2_2')
          end

          expect(output).to include("The `version' component of FreeBSD package names can only include")
        end
      end
    end

    describe '#safe_architecture' do
      context 'when 64-bit' do
        before do
          stub_ohai(platform: 'freebsd', version: '10.0') do |data|
            data['kernel']['machine'] = 'amd64'
          end
        end

        it 'returns amd64' do
          expect(subject.safe_architecture).to eq('x86:64')
        end
      end

      context 'when not 64-bit' do
        before do
          stub_ohai(platform: 'freebsd', version: '10.0') do |data|
            data['kernel']['machine'] = 'i386'
          end
        end

        it 'returns the value' do
          expect(subject.safe_architecture).to eq('x86:32')
        end
      end
    end
  end
end
