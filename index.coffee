path = require 'path'
fs = require 'fs'
events = require 'events'
async = require 'async'

existsSync = fs.existsSync ? path.existsSync
exists = fs.exists ? path.exists

# simple dependency injection. No nesting, just pure simplicity
exports.container = ->

  factories = {}

  # A counter for temporary names used in resolving dependencies.
  resolveIndex = 0

  ## REGISTER / PARSE ################################################

  # register it! Parse it for dependencies
  register = (name, func) ->
    if name == Object name
      hash = name
      for name, func of hash
        registerOne name, func
    else
      registerOne name, func

  registerOne = (name, func) ->
    if not func? then throw new Error "cannot register null function"
    factories[name] = toFactory func

  # Load a directory or file synchronously.
  loadSync = (file) ->
    if existsSync file
      stats = fs.statSync file
      if stats.isDirectory() then return loaddir file
    loadfile file

  # Load a directory or file asynchronously.
  load = (file, cb) ->
    return loadSync file unless cb?
    exists file, (exists) ->
      return loadfile file, cb unless exists
      fs.stat file, (err, stats) ->
        return cb err if err?
        return loaddir file, cb if stats.isDirectory()
        loadfile file, cb

  # Load a file asynchronously, or synchronously if no callback provided.
  loadfile = (file, cb) ->
    module = file.replace(/\.\w+$/, "")

    # Remove dashes from files and camelcase results
    name = path.basename(module).replace(/\-(\w)/g, (match, letter) -> letter.toUpperCase())

    try
      func = require module
    catch err
      return cb err if cb?
      throw err

    register name, func
    cb null, func if cb?

  # Load a directory asynchronously, or synchronously if no callback provided.
  loaddir = (dir, cb) ->
    return loaddirSync dir unless cb?
    fs.readdir dir, (err, filenames) ->
      return cb err if err?
      files = filenames.map (file) -> path.join dir, file
      loaders = []
      for file in files
        do (file) ->
          return unless file.match /\.(js|coffee)$/
          loaders.push (cb) ->
            fs.stat file, (err, stats) ->
              return cb err if err? or not stats.isFile()
              loadfile file, cb
      async.parallel loaders, cb

  # Load a directory synchronously.
  loaddirSync = (dir) ->
    filenames = fs.readdirSync dir
    files = filenames.map (file) -> path.join dir, file
    for file in files
      continue unless file.match /\.(js|coffee)$/
      stats = fs.statSync file
      if stats.isFile() then loadfile file

  toFactory = (func) ->
    return required: [], func: (-> func) if typeof func isnt "function"
    args = argList func
    isAsync = args[args.length - 1] is "done"
    args.pop() if isAsync
    func: func, required: args, async: isAsync

  argList = (func) ->
    # match over multiple lines
    match = func.toString().match /function.*?\(([\s\S]*?)\)/
    if not match? then throw new Error "could not parse function arguments: #{func?.toString()}"
    required = match[1].split(",").filter(notEmpty).map((str) -> str.trim())
    return required

  notEmpty = (a) -> a

  # Fetch/resolve a dependency asynchronously, or synchronously if no callback
  # provided.
  get = (name, overrides, cb) ->
    [cb, overrides] = [overrides, null] if typeof overrides is "function"
    return getSync arguments... unless cb?
    return cb new Error "cannot get dependency without a name" unless name?
  
    try
      dependencies = autoDeps name, overrides
    catch err
      return cb err

    async.auto dependencies, (err, results) ->
      return cb err if err?
      cb null, results[name]

  depMissing = (name) -> new Error "dependency '#{name}' was not registered"

  # An event emitter to keep track of asynchronously resolved dependencies.
  resolver = new events.EventEmitter

  # Create an `async.auto` compatible list of dependency names followed by an
  # `async.auto` compatible resolver function.
  autoDep = (name, overrides) ->
    factory = factories[name]
    return null unless factory?

    # If the dependency exists in the overrides, simply return a callback.
    return ((cb) -> cb null, overrides[name]) if overrides?[name]?

    # `async.auto` callback
    cb = (cb, results) ->
      if not overrides?
        # Return a pre-existing dependency instance if there is one.
        return cb null, factory.instance if factory.instance?
        # If the dependency is already asynchronously resolving, return it once
        # it is resolved.
        return resolver.once name, cb if factory.resolving

      # Fetch the required dependency instances from the `async.auto` results.
      args = (results[req] for req in factory.required)

      if factory.async
        # Flag this dependency as resolving
        factory.resolving = true unless overrides?

        # Create a `done` callback for the asynchronous dependency.
        args.push (err, result) ->
          if err?
            # Notify other async resolvers that this dependency has resolved.
            resolver.emit name, err, result unless overrides?
            return cb err

          if not overrides?
            # Store asynchronous factory instance.
            factory.instance = result
            factory.resolving = false
            # Notify other async resolvers that this dependency has resolved.
            resolver.emit name, err, result
          cb null, result

      try
        # Create the dependency instance
        instance = factory.func args...
      catch err
        return cb err
      if not factory.async
        # Store synchronous factory instance.
        factory.instance = instance unless overrides?
        cb null, instance
  
    return cb if factory.required.length is 0
    [factory.required..., cb]

  # Create an `async.auto` compatible dependency map. Throws an exception if
  # a specified dependency does not exist.
  autoDeps = (name, overrides) ->
    throw depMissing name unless factories[name]?
    dependencies = {}
    for dep in [name, allDeps(name, overrides)...]
      dependencies[dep] ?= autoDep dep, overrides
    dependencies

  # Fetch the expanded, unique list of all dependencies for a given dependency.
  # Checks for circular dependencies, throwing an exception if found.
  allDeps = (name, overrides) ->
    throw depMissing name unless factories[name]?
    return [] if overrides?[name]?
    deps = factories[name].required.concat (allDeps dep for dep in factories[name].required)...
    throw new Error "circular dependency with '#{name}'" if name in deps
    deps.filter (dep, i, deps) -> deps.lastIndexOf(dep) is i
          

  ## GET ########################################################
  # gives you a single dependency

  # recursively resolve it!
  # TODO add visitation / detect require loops
  getSync = (name, overrides, visited = []) ->
    throw new Error "cannot get dependency without a name" unless name?

    isOverridden = overrides?

    # check for circular dependencies
    if haveVisited visited, name
      throw new Error "circular dependency with '#{name}'"
    visited = visited.concat(name)

    factory = factories[name]
    if not factory?
      throw depMissing name

    # use the one you already created
    if factory.instance? and not isOverridden
      return factory.instance

    if factory.async
      throw new Error "dependency '#{name}' is asynchronous but was requested synchronously"

    # apply args to the right?
    dependencies = factory.required.map (name) ->
      if overrides?[name]?
        overrides?[name]
      else
        getSync name, overrides, visited

    instance = factory.func dependencies...

    if not isOverridden
      factory.instance = instance

    return instance

  haveVisited = (visited, name) ->
    isName = (n) -> n is name
    visited.filter(isName).length

  ## RESOLVE ##########################################################

  resolve = (overrides, func) ->
    if not func
      func = overrides
      overrides = null

    # Create and register a temporary dependency, incrementing the resolveIndex
    # to prevent name collisions if multiple resolves are called asynchronously.
    resolveIndex = resolveIndex + 1
    name = "__temp_#{resolveIndex}"
    register name, func

    # Resolve the temporary dependency asynchronously.
    get name, overrides, (err, result) ->
      # Remove the temporary dependency and throw any errors.
      delete factories[name] if factories[name]?
      throw err if err?

  container =
    get: get
    resolve: resolve
    register: register
    load: load

  # let people access the container if the know what they're doing
  container.register "_container", container

  return container

