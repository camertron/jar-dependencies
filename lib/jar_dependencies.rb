#
# Copyright (C) 2014 Christian Meier
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

module Jars
  HOME = 'JARS_HOME'
  MAVEN_SETTINGS = 'JARS_MAVEN_SETTINGS'
  SKIP = 'JARS_SKIP'
  VERBOSE = 'JARS_VERBOSE'
  DEBUG = 'JARS_DEBUG'
  VENDOR = 'JARS_VENDOR'

  if defined? JRUBY_VERSION
    def self.to_prop( key )
      java.lang.System.getProperty( key.downcase.gsub( /_/, '.' ) ) ||
        ENV[key.upcase.gsub( /[.]/, '_' ) ]
    end
  else
    def self.to_prop( key )
      ENV[ key.upcase.gsub( /[.]/, '_' ) ]
    end
  end

  def self.to_boolean( key )
    prop = to_prop( key )
    # prop == nil => false
    # prop == 'false' => false
    # anything else => true
    prop == '' or prop == 'true'
  end

  def self.skip?
    to_boolean( SKIP )
  end

  def self.verbose?
    to_boolean( VERBOSE )
  end

  def self.debug?
    to_boolean( DEBUG )
  end

  def self.vendor?
    to_boolean( VENDOR )
  end

  def self.absolute( file )
    File.expand_path( file ) if file
  end

  def self.reset
    @_jars_maven_settings_ = nil
    @_jars_home_ = nil
    @@jars ||= {}
    @@jars.clear
  end

  def self.maven_settings
    if @_jars_maven_settings_.nil?
      unless @_jars_maven_settings_ = absolute( to_prop( MAVEN_SETTINGS ) )
        # use maven default settings
        @_jars_maven_settings_ = File.join( ENV[ 'HOME' ], 
                                            '.m2', 'settings.xml' )
      end
    end
    @_jars_maven_settings_
  end

  def self.home
    if @_jars_home_.nil?
      unless @_jars_home_ = absolute( to_prop( HOME ) )
        begin
          require 'rexml/document'
          doc = REXML::Document.new( File.read( maven_settings ) )
          REXML::XPath.first( doc, "//settings/localRepository").tap do |e|  
            @_jars_home_ = e.text.sub( /\\/, '/') if e
          end
        rescue
          # ignore
        end
      end
      # use maven default repository
      @_jars_home_ ||= File.join( ENV[ 'HOME' ], '.m2', 'repository' )
    end
    @_jars_home_
  end

  def self.require_jar( group_id, artifact_id, *classifier_version )
    version = classifier_version[ -1 ]
    classifier = classifier_version[ -2 ]

    @@jars ||= {}
    coordinate = "#{group_id}:#{artifact_id}"
    coordinate += ":#{classifier}" if classifier
    if @@jars.key? coordinate
      if @@jars[ coordinate ] == version
        false
      else
        # version of already registered jar
        @@jars[ coordinate ]
      end
    else
      do_require( group_id, artifact_id, version, classifier )
      @@jars[ coordinate ] = version
      return true
    end
  end

  private

  def self.to_jar( group_id, artifact_id, version, classifier )
    file = "#{group_id.gsub( /\./, '/' )}/#{artifact_id}/#{version}/#{artifact_id}-#{version}"
    file += "-#{classifier}" if classifier
    file += '.jar'
    file
  end

  def self.do_require( *args )
    jar = to_jar( *args )
    file = File.join( home, jar )
    # use jar from local repository if exists
    if File.exists?( file )
      require file
    else
      # otherwise try to find it on the load path
      require jar
    end
  rescue LoadError => e
    raise "\n\n\tyou might need to reinstall the gem which depends on the missing jar\n\n" + e.message + " (LoadError)"
  end

  def self.freeze_loading
    ENV[ SKIP ] = 'true'
  end
end

def require_jar( *args )
  return false if Jars.skip?
  result = Jars.require_jar( *args )
  if result.is_a? String
    warn "jar coordinate #{args[0..-2].join( ':' )} already loaded with version #{result}"
    return false
  end
  result
end
