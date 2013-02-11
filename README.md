# Kongo

Kongo is a lightweight and generic library for accessing data from Mongo.

## Rationale

Kongo is not your typical ORM. Traditionally, according to MVC architecture best practices, you would create a model class to represent data from each collection in your application. However, while it is a good abstraction early on, as an application grows and scales, it is not uncommon to see models grow to thousands of lines of code, grouping together many different pieces of unrelated business logic. Not only that, but dependencies and tight coupling arises between the various related models.

Kongo takes a different approach. Kongo does not have models, it simply provides basic data-access functionality and object-oriented wrapping of the Mongo driver. It also provides support for extending collections and models with libraries. Kongo believes logic belongs in libraries, and related code belongs in the same file, not divided amongst multiple models and mixed with other logic.

## Usage

Using Kongo is fairly straight-forward.

First, however, Kongo must know how to connect to Mongo (put this in a init / config type file):

```ruby
db = Mongo::Connection.new(...)['dbname']
Kongo::Collection.fetch_collections_using do |collection_name|
  # In larger applications you would insert logic here to figure out
  # how to connect to Mongo, when you have multiple replicated or
  # sharded clusters...
  db[collection_name]
end
```

Then, simply define your collections as you use them. (It's okay to do this in multiple contexts).

```ruby
Posts = Kongo::Collection.new(:posts)
Comments = Kongo::Collection.new(:comments)
```

You can use a collection to read data:

```ruby
post = Posts.find_by_id(id)

# this returns a cursor
comments = Comments.find_many(post: post._id)

# get a json of the top ten comments
top = comments.sort(score: -1)
json = top.to_enum.take(10).map(:&to_hash).to_json
```

All Kongo methods yield `Kongo::Model` objects whenever possible. These objects simply wrap around a `Hash` and provide some helper methods for dealing with the object.

Perhaps the most useful of these helpers is `update!`:

```ruby
# Kongo encourages only performing atomic updates:

# simple setters change the data and record the appropriate delta
post.title = 'New title!'
post.date = Time.now.to_i
# more advanced deltas can be set explicitly. see mongo update syntax for documentation.
post.delta('$inc', edit_count: 1)

# the update! method commits deltas.
post.update!
```

This is just the tip of the iceberg. See the documentation for the Kongo classes to see everything that Kongo can do.

### Writing an extension

Imagine you have three models, `user`, `account`, and `transaction`. You want to make a library that will let you transfer money between users and their accounts. Typically you'd add code to your three existing model classes:

models/user.rb:

```ruby
require 'models/account'

class User < Model

  # a whole bunch of random crap
  # ...

  def earnings
    Account::find_by_id(self['earnings_account'])
  end
  def spend
    Account::find_by_id(sefl['spend_account'])
  end
end
```

models/account.rb:

```ruby
require 'models/transaction'
class Account < Model
  # more random crap
  def deposit; ...; end

  def transfer_to(other_account, amount)
    if Transaction.create(self, other_account, amount})
    self.update!('$inc', amount: (-1 * amount))
    other_account('$inc', amount: amount)
  end
end
```

models/transaction.rb:

```ruby
class Transaction < Model
  def self.create(from, to, amount)
    if from.balance >= amount
      insert!({form: from['_id'], to: to['_id'], amount: amount})
      true
    else
      false
    end
  end
end
```

Now we have code related to the same thing in three different model files, and it's all mixed up with the other functionality of these models (such as analytics for transactions or authentication for the user model).

Instead, if we have the possibility of abstracting this into a library, we might have something much cleaner like a single `lib/finance.rb` file:

```ruby
module Finance

  # other finance functionality that does not belong directly to a
  # model, eg something like inance::convert_currency
  # our finance extensions to the models:

  module Extensions
    module User
      def earnings
        Account::find_by_id(self['earnings_account'])
      end
      def spend
        Account::find_by_id(sefl['spend_account'])
      end
    end
    Kongo::Model.add_extension(:users, User)

    module Transactions
      def create(from, to, amount)
        if from.balance >= amount
          insert!({form: from['_id'], to: to['_id'], amount: amount})
          true
        else
          false
        end
      end
    end
    Kongo::Collection.add_extension(:transactions, Transactions)

    TransactionsCollection = Kongo::Collection.new(:transactions)
    module Account
      def deposit; ...; end
      def transfer_to(other_account, amount)
        if TransactionsCollection.create(self, other_account, amount})
        self.update!('$inc', amount: (-1 * amount))
        other_account('$inc', amount: amount)
      end
    end
    Kongo::Model.add_extension(:accounts, Account)

  end

  # The Account and Transaction "models" belong to the finance library,
  # in that it is their primary function. So we provide constants for them:
  Acounts = Kongo::Collection.new(:accounts)
  Transactions = Kongo::Collection.new(:transactions)
end
```

Using this extension is now straight-forward:

```ruby
require 'lib/authentication' # imagine this lib provides user-related functionality
require 'lib/finance'
user = Authentication.current_user
kenneth = Authentication::Users.find_one(email: 'kenneth@ballenegger.com')
user.transfer_to(kenneth, 100)
```

## Installation

Add this line to your application's Gemfile:

    gem 'kongo'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kongo

## Contributing

1. Fork it
2. Create your feature branch (```git checkout -b my-new-feature```)
3. Commit your changes (```git commit -am 'Add some feature'```)
4. Push to the branch (```git push origin my-new-feature```)
5. Create new Pull Request
