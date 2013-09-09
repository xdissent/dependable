# Dependable

A minimalist dependency injection framework for node.js.

## Example

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

## Helpful Tips

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

