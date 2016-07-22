childProcess = require 'child_process'
fs = require 'fs'
path = require 'path'

async = require 'async'
_ = require 'lodash'
rimraf = require 'rimraf'

# Information about a package installed by npm.
class NpmPackage
  # @return {string} the package's computed name
  name: null

  # @return {string} the filesystem path where the package is installed
  path: null

  # @return {Object} the data in the package's package.json file
  json: null

  # @return {string} the npm package version or source
  version: null

  # Bundles information for a package.
  #
  # @param {string} path the filesystem path where the package is installed
  # @param {Object} packageJson the data in the package's package.json file
  constructor: (path, packageJson) ->
    @path = path
    @json = packageJson
    @name = @_extractName()
    @version = @_extractVersion()

  # Computes a package's name from other data.
  #
  # @return {string} the package's name
  _extractName: ->
    @json.name

  # Computes the package's version from its package.json contents.
  #
  # @return {string} a specifier that can be added to a package.json file to
  #  install this package's exact version
  _extractVersion: ->
    from = @installFrom()
    if from is "#{@_extractName()}@#{@json.version}"
      @json.version
    else
      from

  # Lists the files in this package that differ from their versions in git.
  #
  # @param {function(Error, Array<string>)} callback called with the files in
  #  this package that differ from their git versions
  changedFiles: (callback) =>
    childProcess.exec @changedFilesGitCommand(), (error, stdout, stderr) =>
      if error
        callback error
        return

      files = []
      _.forEach stdout.split('\0'), (line) =>
        fields = _.map line.trim().split(/\s+/), _.trim
        return unless fields.length >= 2
        if fields[0] isnt '0' or fields[1] isnt '0'
          gitFile = fields[2]
          files.push path.relative(@path, path.resolve(gitFile))

      callback null, files

  # A shell command that will obtain the list of changed files in this package.
  #
  # @return {string} the shell command
  changedFilesGitCommand: ->
    "git diff --ignore-space-at-eol --no-renames --numstat -z -- #{@path}"

  # Installs this npm package.
  #
  # @param {function(Error)} callback called when this package is installed
  install: (callback) =>
    childProcess.exec @installCommand(), (error, stdout, stderr) ->
      callback error

  # A shell command that will install this package.
  #
  # @return {string} the shell command that will install this exact package
  installCommand: ->
    "npm install #{@installFrom()}"

  # The npm source that this package should be installed from.
  #
  # @return {string} the npm source that will install this exact package
  installFrom: ->
    # Private packages cannot be installed from npm, by definition.
    if @json.private
      return null

    if @json._from
      # Handle "npm install git+https://github.com/legit-repo#branch".

      # Some npm versions dump an arbitrary filesystem path in the _from when
      # the command above is used. Work around them.
      if @json._from.indexOf('../') isnt -1 and @json._resolved
        return @json._resolved

      if @json._from.indexOf('@') is -1 and @json._from.indexOf('../') is -1
        return @json._from

    # Packages installed with recent npm versions have an _id field that
    # contains the name and version.
    return @json._id if @json._id

    # We can compute the _id field if we have a name and a version.
    if @json.name and @json.version
      return "#{@json.name}@#{@json.version}"

    # No clue how to get this installed.
    null

  # Checks if this package's own files are different from their git versions.
  #
  # @param {function(Error, boolean)} callback called with true if the package
  #   is changed, or false otherwise
  isChanged: (callback) =>
    @changedFiles (error, files) ->
      if error
        callback error
        return

      packageFiles = _.reject files, (file) ->
        (file is 'package.json') or (file.indexOf('node_modules') isnt -1)
      callback null, not _.isEmpty(packageFiles)

  # Checks if this package's git version carries patches from the npm version.
  #
  # @param {function(Error, boolean)} callback called with true if the package
  #   is patched, or false otherwise
  isPatched: (callback) =>
    # Handle packages that don't even exist on npm.
    if @installFrom() is null
      callback null, true
      return

    async.series [@reinstall, @isChanged], (error, results) ->
      if error
        callback error
        return
      callback null, results[1]

  # Removes and then installs this npm package.
  #
  # @param {function(Error)} callback called when this package is removed and
  #   then reinstalled
  reinstall: (callback) =>
    sequence = [@remove, @install]
    sequence.push @dosToUnix if @useDosToUnix
    async.series sequence, _.ary(callback, 1)

  # Removes this npm package.
  #
  # This removes the package's directory under the node_modules/ directory. It
  # does nothing regarding packages that may depend on this package.
  #
  # @param {function(Error)} callback called when the package is removed
  remove: (callback) =>
    rimraf @path, callback

  # Selects packages matching a specific name.
  #
  # @param {string} name the package name to filter for
  # @param {Array<NpmPackage>} packages the packages to be filtered
  # @return {Array<NpmPackage>} the packages that match the name filter
  @filterByName = (packages, name) ->
    _.filter packages, (npmPackage) -> npmPackage.name is name

  # Checks if a path contains a npm package.
  #
  # @param {string} packagePath the path to be checked
  # @return {function(Error, boolean)} callback called with the result of the
  #   check
  @isPackagePath: (packagePath, callback) ->
    jsonPath = path.join packagePath, 'package.json'
    fs.exists jsonPath, callback

  # Builds up a list of the packages installed in the node_modules/ directory.
  #
  # @param {function(Error, Array<NpmPackage})} callback called with an array
  #   of NpmPackage instances describing the packages installed in node_modules
  @list: (callback) =>
    modulesPath = path.normalize path.join(process.cwd(), 'node_modules')
    entries = fs.readdirSync modulesPath

    packagePaths = _(entries).map((entry) ->
      path.join(modulesPath, entry)).value()
    async.filter packagePaths, @isPackagePath, (packagePaths) =>
      async.map packagePaths, @readFrom, callback

  # Builds the object describing a package under node_modules/.
  #
  # @param {String} packagePath the path to be checked
  # @return {function(Error, NpmPackage)} callback called with the NpmPackage
  #   instance describing the package at the given path
  @readFrom: (packagePath, callback) ->
    jsonPath = path.join packagePath, 'package.json'
    fs.readFile jsonPath, encoding: 'utf8', (error, jsonText) ->
      if error
        async.setImmediate -> callback error
        return
      try
        json = JSON.parse jsonText
      catch jsonError
        async.setImmediate -> callback jsonError
        return

      packageJson = new NpmPackage(packagePath, json)
      callback null, packageJson

  # Sorts an array of NpmPackages by name.
  #
  # @param {Array<NpmPackage>} packages the packages that will be sorted
  # @return {Array<NpmPackage>} sorted packages
  @sortedByName = (packages) ->
    _.sortBy packages, (npmPackage) -> npmPackage.name

module.exports = NpmPackage
