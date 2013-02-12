require 'mongoid'

Mongoid.load!("mongoid.yaml", :development)

class Pattern
  include Mongoid::Document
  field :pattern, type: Array
  field :n, type: Integer
  field :count, type: Integer, default: 0
  field :code, type: Array, default: []
  
  scope :of_n, ->(n){where(n: n)}
  scope :including, ->(p){where(:pattern.in => [ p ])}
  
end

Pattern.new({
  :pattern => ["hello!"],
  :n => 1,
  :code => [
    {:line => 1, :code => "int x\nx=2"}
    ]
}).save