#
# Copyright 2015 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
=begin
pre-install
post-install
install
pre-deinstall
post-deinstall
deinstall
pre-upgrade
post-upgrade
upgrade
=end

module Omnibus
  class Packager::PKGNG < Packager::Base
    id :pkgng
    # @return [Hash]
    SCRIPT_MAP = {
      # Default Omnibus naming
      preinst:  'pre-install',
      postinst: 'post-install',
      prerm:    'pre-deinstall',
      postrm:   'post-deinstall',
      # Default PKGNG naming
      preinstall:          'pre-install',
      postinstall:         'post-install',
      install:             'install',
      predeinstall:        'pre-deinstall',
      deinstall:           'deinstall',
      preupgrade:          'pre-upgrade',
      postupgrade:         'post-upgrade',
      upgrade:             'upgrade',
    }.freeze
    
    PREFIX='/'
    
    setup do
      # Copy the full-stack installer into our scratch directory, accounting for
      # any excluded files.
      #
      # /opt/hamlet => /tmp/daj29013/opt/hamlet
      destination = File.join(staging_dir, project.install_dir)
      FileSyncer.sync(project.install_dir, destination, exclude: exclusions)

      # Copy over any user-specified extra package files.
      #
      # Files retain their relative paths inside the scratch directory, so
      # we need to grab the dirname of the file, create that directory, and
      # then copy the file into that directory.
      #
      # extra_package_file '/path/to/foo.txt' #=> /tmp/scratch/path/to/foo.txt
      project.extra_package_files.each do |file|
        parent      = File.dirname(file)
        destination = File.join(staging_dir, parent)

        create_directory(destination)
        copy_file(file, destination)
      end

    end

    build do
      
      compact_manifest = generate_compact_manifest
      manifest = generate_manifest(compact_manifest)
      inject_scripts(manifest)
      
      # Write the compact manifest
      write_manifest(compact_manifest, '+COMPACT_MANIFEST')

      # Write the full manifest
      write_manifest(manifest, '+MANIFEST')
      
      # Create the package
      create_package
    end

    #
    # @!group DSL methods
    # --------------------------------------------------
    
    #
    # Set or return the package name for this package.
    #
    # @example
    #   package_name "omnibus-chef"
    #
    # @param [String] val
    #   the package name for this package
    #
    # @return [String] 
    #   the package name for this package
    #
    def base_package_name(val = NULL)
      if null?(val)
        @package_name || project.package_name
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:base_package_name, 'be a String')
        end

        @package_name = val
      end
    end
    expose :base_package_name

    #
    # Set or return the license for this package.
    #
    # @example
    #   licenses ["Apache 2.0"]
    #
    # @param [Array<String>] licenses
    #   the list of licenses for this package
    #
    # @return [Array<String>] licenses
    #   the list of licenses for this package
    #
    def licenses(val = NULL)
      if null?(val)
        @licenses || ['unknown']
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:licenses, 'be a String')
        end

        @licenses = val
      end
    end
    expose :licenses
    
    #
    # Set or return the license for this package.
    #
    # @example
    #   licenselogic "single"
    #
    # @param [String] val
    #   the licenselogic for this package (single, dual, multi, or, and)
    #
    # @return [String]
    #   the licenselogic for this package (single, dual, multi, or, and)
    #
    def licenselogic(val = NULL)
      if null?(val)
        @licenselogic || 'single'
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:licenselogic, 'be a String')
        end

        @license = val
      end
    end
    expose :licenselogic
    
    #
    # Set or return the origin for this package.
    #
    # @example
    #   origin "databases/mysql"
    #
    # @param [String] val
    #   the origin for this package
    #
    # @return [String]
    #   the origin for this package
    #
    def origin(val = NULL)
      if null?(val)
        @origin || "misc/#{safe_base_package_name}"
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:origin, 'be a String')
        end

        @origin = val
      end
    end
    expose :origin
    
    #
    # Set or return the comment for this package.
    #
    # @example
    #   comment "The mysql package"
    #
    # @param [String] val
    #   the section for this package
    #
    # @return [String]
    #   the section for this package
    #
    def comment(val = NULL)
      if null?(val)
        @comment || "The #{safe_base_package_name} package"
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:comment, 'be a String')
        end

        @comment = val
      end
    end
    expose :comment
    
    #
    # @!endgroup
    # --------------------------------------------------

    #
    # The name of the package to create.
    #
    def package_name
      "#{safe_base_package_name}-#{safe_version}-#{safe_osversion}-#{Ohai['kernel']['machine']}.txz"
    end
        
    #
    # Generates and returns the package compact manifest as a Hash
    #
    # @return [Hash]
    #
    def generate_compact_manifest
      {
        'prefix' => PREFIX,
        'name' => safe_base_package_name,
        'version' => safe_version,
        'arch' => safe_architecture,
        'origin' => origin,
        'comment' => comment,
        'maintainer' => project.maintainer,
        'www' => project.homepage,
        'desc' => project.description,
        'licenselogic' => licenselogic,
        'licenses' => licenses
      }
    end
    
    #
    # Search the package staging directory for files and directories.
    # Files should be checksumed with SHA256.  Note that this forces ownerships
    # of the files and directories in the package to root:wheel.  The results
    # are merged with the compact manifest.
    #
    # @param [Hash] val
    #   The compact manifest for the current package.
    #
    # @return [Hash]
    #
    def generate_manifest(compact_manifest)
      content_hash = {'flatsize' => 0, 'files' => {}, 'directories' => {}}
      content_hash = FileSyncer.glob("#{staging_dir}/**/*").inject(content_hash) do |ch, path|
        estat = File.lstat(path)
        ekey = path.gsub(/#{staging_dir}\//, '/')
        eperm = sprintf("%o", estat.mode)
        eperm = eperm[(eperm.size-4)..eperm.size]
        if estat.file?
          ch['flatsize'] += File.new(path).size
          ch['files'][ekey] = {'sum' => digest(path, :sha256), 'uname' => 'root', 'gname' => 'wheel', 'perm' => eperm}
        elsif estat.directory?
          ch['flatsize'] += File.new(path).size 
          ch['directories'][ekey] = {'uname' => 'root', 'gname' => 'wheel', 'perm' => eperm}
        elsif estat.symlink?
          ch['files'][ekey] = '-'
        end
        ch
      end
      compact_manifest.merge(content_hash)
    end
    
    def inject_scripts(manifest)
      scripts = SCRIPT_MAP.inject({}) do |hash, (source, destination)|
        path =  File.join(project.package_scripts_path, source.to_s)

        if File.file?(path)
          hash[destination] = File.read(path)
        end

        hash
      end
      manifest['scripts'] = scripts
      manifest
    end
 
    #
    # Write the specified manifest file
    #
    # @param [Hash] val
    #   The manifest that is being written
    #
    # @param [String] val
    #   The manifest file name (relative to the staging directory)
    #
    # @return [void]
    #
    def write_manifest(manifest, manifest_file)
      File.open("#{staging_dir}/#{manifest_file}", 'w') do |f|
        f.write(manifest.to_json)
      end
    end

    #
    # Create the +.txz+ package file, then move it to {package_name}.
    #
    # @return [void]
    #
    def create_package
      
      log.info(log_key) { "Creating package" }

      # Execute the build command
      Dir.chdir(Config.package_dir) do
        pkgName = "#{safe_base_package_name}-#{project.build_version}_#{safe_build_iteration}.txz"
        shellout!("/usr/sbin/pkg create -r #{staging_dir} -o #{Config.package_dir} -m #{staging_dir}")
        FileSyncer.glob("#{Config.package_dir}/#{pkgName}").each do |pkg|
          copy_file(pkg, package_name)
        end
      end
    end
    

    #
    # Return the base package name, converting any invalid characters to
    # dashes (+-+).
    #
    # @return [String]
    #
    def safe_base_package_name
      if base_package_name =~ /\A[a-z0-9\.\+\-]+\z/
        base_package_name.dup
      else
        converted = base_package_name.downcase.gsub(/[^a-z0-9\.\+\-]+/, '-')

        log.warn(log_key) do
          "The `name' component of FreeBSD package names can only include " \
          "lower case alphabetical characters (a-z), numbers (0-9), dots (.), " \
          "plus signs (+), and dashes (-). Converting `#{base_package_name}' to " \
          "`#{converted}'."
        end

        converted
      end
    end

    #
    # This is actually just the regular build_iteration, but it felt lonely
    # among all the other +safe_*+ methods.
    #
    # @return [String]
    #
    def safe_build_iteration
      project.build_iteration
    end

    #
    # Return the package version.
    #
    # @return [String]
    #
    def safe_version
      version = "#{project.build_version}_#{safe_build_iteration}"
      if (version =~ /[^0-9a-zA-Z._\-,]/)
        version = version.gsub(/[^0-9a-zA-Z._\-,]/, '_')
        version = version.gsub(/_+/, '_')
        log.warn(log_key) do
          "The `version' component of FreeBSD package names can only include " \
          "lower case alphabetical characters (a-z), numbers (0-9), dots (.), " \
          "dashes (-), understores (_) and commas (,)."
        end
      end
      version
    end
    
    #
    # Return the OS version.
    #
    # @return [String]
    #
    def safe_osversion
      "FreeBSD#{Ohai['platform_version'].to_i}"
    end

    #
    # FreeBSD package architectures are weird.
    #
    # @return [String]
    #
    def safe_architecture
      case Ohai['kernel']['machine']
      when 'amd64'
        'x86:64'
      when 'i386'
        'x86:32'
      end
    end
  end
end
