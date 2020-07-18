# kemal-session-bcdb

A BCDB session Storage backend for [Kemalcr.com](https://kemalcr.com/)


## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     kemal-session-bcdb:
       github: crystaluniverse/kemal-session-bcdb
   ```

2. Run `shards install`

## How to use

##### Download, compile & run 0-db (Backend for BCDB)
- `git clone git@github.com:threefoldtech/0-db.git`
- `cd 0-db && make`
- `./zdb --mode seq`

##### Download, compile & run BCDB (Backend for BCDB)
- Install [Rust programming language](https://www.rust-lang.org/tools/install)
- `git clone git@github.com:threefoldtech/bcdb.git`
- `cd bcdb && make`
- copy bcdb binary anywhere `cp bcdb/target/x86_64-unknown-linux-musl/release/bcdb .`
- download `tfuser` utility from [here](https://github.com/crystaluniverse/bcdb-client/releases/download/v0.1/tfuser)
- use `tfuser` to register your 3bot user to explorer and generate seed file `usr.seed` using `./tfuser id create --name {3bot_username.3bot} --email {email}`
- run bcdb : `./bcdb --seed-file user.seed `
- now you can talk to `bcdb` through http via unix socket `/tmp/bcdb.sock`

##### Usage (Kemal.rc example)

```crystal

require "kemal"
require "kemal-session"
require "kemal-session-bcdb"

Kemal::Session.config do |config|
  config.cookie_name = "redis_test"
  config.secret = "a_secret"
  config.engine = Kemal::Session::BcdbEngine.new(unixsocket= "/tmp/bcdb.sock", namespace = "kemal_sessions", key_prefix = "kemal:session:")
  config.timeout = Time::Span.new hours: 0, minutes: 0, seconds: 20
end


get "/set" do |env|
  env.session.int("number", rand(100)) # set the value of "number"
  "Random number set."
end

get "/get" do |env|
  num  = env.session.int?("number") # get the value of "number"
  env.session.int?("hello") # get value or nil, like []?
  "Value of random number is #{num}."
end

get "/destroy" do |env|
  env.session.destroy
  num  = env.session.int?("number")
  env.session.int?("hello") # get value or nil, like []?
  "Value of random number is #{num}."
end
```
