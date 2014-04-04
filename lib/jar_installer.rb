class JarInstaller

  class Dependency
    
    attr_reader :path, :file, :gav, :scope, :type, :coord

    def self.new( line )
      if line.match /:jar:|:pom:/
        super
      end
    end

    def initialize( line )
      if line.match /:pom:/
        @type = :pom
      elsif line.match /:jar:/
        @type = :jar
      end
      line.sub!( /^\s+/, '' )
      @coord = line.sub( /:[^:]+:[^:]+$/, '' )
      first, second = line.sub( /:[^:]+:[^:]+$/, '' ).split( /:#{type}:/ )
      group_id, artifact_id = first.split( /:/ ) 
      parts = group_id.split( '.' ) 
      parts << artifact_id
      parts << second.split( /:/ )[ -1 ]
      parts << File.basename( line.sub /.:/, '' ) 
      @path = File.join( parts ).strip
      
      @scope = 
        case line
        when /:provided:/
          :provided
        when /:test:/
          :test
        else
          :runtime
        end
      line.gsub!( /:jar:|:pom:|:test:|:compile:|:runtime:|:provided:/, ':' )
      @file = line.sub( /^.*:/, '' ).strip
      @gav = line.sub( /:[^:]+$/, '' )
    end
  end

  def self.install_jars
    new.install_jars
  end

  def self.load_from_maven( file )
    result = []
    File.read( file ).each_line do |line|
      dep = Dependency.new( line )
      result << dep if dep
    end
    result
  end

  def self.install_deps( deps, dir, require_filename, vendor )
    FileUtils.mkdir_p( File.dirname( require_filename ) )
    File.open( require_filename, 'w' ) do |f|
      f.puts "require 'jar_dependencies'"
      f.puts
      deps.each do |dep|
        next if dep.type != :jar || dep.scope != :runtime
        args = dep.gav.gsub( /:/, "', '" )
        if vendor
          vendored = File.join( dir, dep.path )
          FileUtils.mkdir_p( File.dirname( vendored ) )
          FileUtils.cp( dep.file, vendored )
          f.puts( "require_jar( '#{args}' )" )
        else
          f.puts( "require_jarfile( '#{dep.file}', '#{args}' )" )
        end
      end
    end
  end

  def initialize( spec = nil )
    if spec.nil?
      specs = Dir[ '*.gemspec' ]
      case specs.size
      when 0
        raise 'no gemspec found'
      when 1
        spec = specs.first
      else
        raise 'more then one gemspec found. please specify a specfile' 
      end
    end
    if spec.is_a? String
      @basedir = File.dirname( File.expand_path( spec ) )
      @specfile = spec
      spec =  eval( File.read( spec ) )
    else
      @basedir = spec.gem_dir
      @specfile = spec.spec_file
    end
    @spec = spec
  end

  def vendor_jars
    return if @spec.requirements.empty?
    really_vendor = java.lang.System.get_property( 'jruby.jars.vendor' ) || ENV[ 'JRUBY_JARS_VENDOR' ] || 'true'
    do_install( really_vendor == 'true' )
  end

  def install_jars
    return if @spec.requirements.empty?
    do_install( false )
  end

  private

  def do_install( vendor )
    vendor_dir = File.join( @basedir, @spec.require_path )
    jars_file = File.join( vendor_dir, "#{@spec.name}_jars.rb" )

    return if File.exists?( jars_file ) && 
      File.mtime( @specfile ) < File.mtime( jars_file )

    self.class.install_deps( install_dependencies, vendor_dir, 
                             jars_file, vendor )
  end

  def install_dependencies
    deps = File.join( @basedir, 'deps.lst' )

    # lazy load ruby-maven
    begin

      require 'maven/ruby/maven'

    rescue LoadError
      raise 'please install ruby-maven gem so the jar dependencies can be installed'
    end
   
    # monkey patch to NOT include gem dependencies
    require 'maven/tools/gemspec_dependencies'
    eval <<EOF
      class ::Maven::Tools::GemspecDependencies
        def runtime; []; end
        def development; []; end
      end
EOF

    maven = Maven::Ruby::Maven.new
    maven.exec 'dependency:list', "-DoutputFile=#{deps}", '-DincludeScope=runtime', '-DoutputAbsoluteArtifactFilename=true', '-DincludeTypes=jar', '-DoutputScope=true', '-f', @specfile, '--quiet'

    self.class.load_from_maven( deps )
  ensure
    FileUtils.rm_f( deps ) if deps
  end
end
