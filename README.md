# Dependable

A minimalist dependency injection framework for javascript (fully tested for node.js)

## Goals

1. Allow creation of modules that can be passed dependencies instead of requiring them. 
2. Simple bootstrapping, minimal footprint
3. Automatic

## Documentation

### What is Dependency Injection
In CommonJS, modules are normally defined like one of the following

```js
var hello = module.exports = { hello: "hello world" };
hello.hello = function () { return "hello world" };
```

If you have a dependency, you normally just require it. The `greetings` module needs some config to work. 

```js
var Greetings = require("greetings"),
    greetings = new Greetings("en");

module.exports = function () {
  return {
    hello: function () { return greetings.hello("world"); }
  }
};
```

Instead of requiring it, and setting the config inside our module, we can require that a pre-configured greetings instance be passed in to our function.

```js
module.exports = function (greetings) {
  return {
    hello: function () { return greetings.hello("world"); }
  };
};
```

This is "Dependency Injection". `greetings` is a dependency of our module. Its dependencies are "injected", meaning they are handed to us by whoever uses our module instead of us reaching out for them. 

### Why Dependency Injection?

If you ever need to change your config options, such as when testing, or to hit different layers of a service, it is easier to have a pre-configured object passed in instead of creating it yourself.

Your module is a little less coupled to its dependency

You can pass in mock or alternate versions of a module if you want

### This is Annoying

It is hard to remember how to construct and configure the dependencies when you want to use your module. This should be automatic.  Here is an example

`robot.js`:
```js
module.exports = function (greetings) {
  return {
    hello: function () { return greetings.hello("world"); }
  };
};
```

`greetings.js`:
```js
module.exports = function (language) {
  if (language === 'en') {
    return {
      hello: function (place) { return "hello " + friend; }
    };
  }
  throw new Error('ENOTIMPLEMENTED');
};
```

`app.js`:
```js
// you have to do this in every file you want to use robot
var Greetings = require("greetings"),
    greetings = Greetings("en");

var Robot = require("robot"),
    robot = Robot(greetings);

console.log(Robot.hello()); // hello world
```

*This gets much worse* when your dependencies have dependencies of their own. You have to remember in which order to configure them so you can pass them into each other. 

### Using Dependenable

Dependable automates this process. In the following example, you don't need to register the modules in order, or do it more than once (it will work for dependencies of dependencies)

`robot.js`:
```js
module.exports = function (greetings) {
  return {
    hello: function () { return greetings.hello("world"); }
  };
};
```

`greetings.js`:

```js
module.exports = function (language) {
  if (language === 'en') {
    return {
      hello: function (place) { return "hello " + friend; }
    };
  }
  throw new Error('ENOTIMPLEMENTED');
};
```

`app.js`:
```js
var container = require('dependable').container,
    deps = container();

deps.register("greetings", require("greetings"));
deps.register("robot", require("robot"));

deps.resolve(function (robot) {
  console.log(robot.hello()); // "hello world"
});
```

### Using Dependable's Load

You can load files or directories instead of registering by hand. See [Reference](#reference)
 
### Overriding Dependencies for Testing

When testing, you usually want most dependencies loaded normally, but to mock others. You can use overrides for this. In the example below, `User` depends on `Friends.getInfo` for it's `getFriends` call. By setting `Friends` to `MockFriends` we can stub the dependency, but any other dependencies `User` has will be passed in normally.

`bootstrap.js`:
```js
var container = require('dependable').container,
    deps = container();

deps.register("Friends", require('./Friends'));
deps.register("User", require('./User'));

module.exports = deps;
```

`test.js`:
```js
var deps = require('../lib/bootstrap.js');

describe('User', function () {
  it('should get friends plus info', function (done) {
    var MockFriends = {
      getInfo: function (id, cb) { cb(null, { some: 'info' }); }
    };

    //
    // Override the 'Friends' dependency with your mock
    //
    var User = deps.get('User', { Friends: MockFriends });

    user.getFriends('userId', function (err, friends) {
      assert(!err);
      done();
    });
```

## Reference

`container.register(name, function)` - registers a dependency by name. `function` can be a function that takes dependencies and returns anything, or an object itself with no dependencies.

`container.register(hash)` - registers a hash of names and dependencies. Useful for config.

`container.load(fileOrFolder)` - registers a file, using its file name as the name, or all files in a folder. Does not follow sub directories

`container.get(name, overrides = {})` - returns a module by name, with all dependencies injected. If you specify overrides, the dependency will be given those overrides instead of those registerd. 

`container.resolve([overrides,] cb)` - calls cb like a dependency function, injecting any dependencies found in the signature

```js
deps.resolve(function (User) {
  // do something with User
});
```

