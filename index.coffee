async = require 'async'
_ = require 'lodash'

NpmPackage = require './npm_package'

{argv} = require 'yargs'
  .help 'h'
  .alias 'h', 'help'
  .usage '''
    Find npm packages installed in node_modules.

    Usage: $0
    '''
  .option 'find-patched',
    describe: 'Find packages that carry local patches'
    type: 'boolean'
  .option 'only',
    describe: 'Restrict the computation to a single package'
    type: 'string'
  .option 'reinstall',
    describe: 'Reinstalls npm packages'
    type: 'boolean'

# list_packages without the --find-patched argument.
listPackagesCommand = (finder) ->
  console.log [finder]
  finder (error, packages) ->
    if error
      console.error error
      return

    packages = NpmPackage.sortedByName packages
    depsText = _(packages)
      .map (p) ->
        "    #{JSON.stringify(p.name)}: #{JSON.stringify(p.version)}"
      .join(",\n")

    console.log depsText

# list_packages with the --reinstall argument.
reinstallCommand = (finder) ->
  finder (error, packages) ->
    if error
      console.error error
      return

    packages = NpmPackage.sortedByName packages
    reinstallPackage = (npmPackage, callback) -> npmPackage.reinstall callback
    async.eachSeries packages, reinstallPackage, (error) ->
      if error
        console.error error
        return
      console.log 'Done'

# list_packages with the --find-patched argument.
findPatchedCommand = (finder) ->
  finder (error, packages) ->
    if error
      console.error error
      return

    # :TRICKY: not using async.filterSeries because the version in async < 2.0
    #          has a broken API, and we haven't upgraded to async 2.x yet.
    changedPackages = []
    checkPackage = (npmPackage, callback) ->
      console.log "Checking #{npmPackage.name}"
      npmPackage.isPatched (error, result) ->
        if error
          callback error
          return
        changedPackages.push npmPackage if result
        callback null

    packages = NpmPackage.sortedByName packages
    async.eachSeries packages, checkPackage, (error) ->
      if error
        console.error error
        return

      depsText = _(changedPackages)
        .map (p) ->
          "    #{JSON.stringify(p.name)}: #{JSON.stringify(p.version)}"
        .join(",\n")

      console.log depsText

if argv.only
  finder = (callback) ->
    NpmPackage.list (error, packages) ->
      if error
        callback error
      else
        callback null, NpmPackage.filterByName(packages, argv.only)
else
  finder = NpmPackage.list

command = if argv.findPatched
  findPatchedCommand
else if argv.reinstall
  reinstallCommand
else
  listPackagesCommand

command finder
