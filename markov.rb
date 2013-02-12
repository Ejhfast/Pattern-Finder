require 'ruby2ruby'
require 'ruby_parser'
require 'pp'
require 'mongoid'

# Database stuff
Mongoid.load!("mongoid.yaml", :development)

class Pattern
  include Mongoid::Document
  field :pattern, type: Array
  field :n, type: Integer
  field :count, type: Integer
  field :code, type: Array, default: []
  field :files, type: Array, default: []
  field :projects, type: Array, default: []
  field :bits, type: Integer
  field :p_count, type: Integer
  
  index({ pattern: 1, n: 1 }, { unique: true })
    
  scope :of_n, ->(n){where(n: n)}
  scope :including, ->(p){where(:pattern.in => [ p ])} 
end

class Stats
  include Mongoid::Document
  include Mongoid::Timestamps
  field :loc, type: Integer, default: 0
  field :projects, type: Array, default: []
  field :options, type: Array, default: []
end

# Search through all ruby files in the first argument
files = Dir["#{ARGV[0]}/**/*.rb"]
projects = files.map{|x| x.split("/")[2]}.uniq
DEPTH = ARGV[1].to_i

# Get option list
OPTIONS = ARGV.drop(2) # Possible: --var, --str, --fun, --fargs, --lit, --junk, --just_calls
ast_options = ["--var","--str","--fun", "--fargs", "--lit"]
OPTIONS += ast_options if OPTIONS.include?("--all-ast")

# Save session
MYSTATS = Stats.new(:projects => projects, :options => ARGV.to_a)
MYSTATS.save

# Utility for deep copy
class Object
  def deep_copy
    Marshal.load(Marshal.dump(self))
  end
end

# Helper class for infinitly deep hashes
class InfinityHash < Hash
  def [] key; key?(key) ? super(key) : self[key] = InfinityHash.new end
end

# Process the AST, remove noise
class FuncCalls < SexpProcessor
  
  attr_accessor :just_calls
  
  def initialize(f,options)
    @file = f
    @options = options
    @just_calls = []
    @call_depth = []
    #@iter_depth = []
    super()
    self.strict = false
    #self.expected = String
    self.require_empty = false
  end
  def process_lit(exp)
    if @options.include?("--lit")
      return s(:lit, "LITERAL")
    else
      exp
    end
  end
  def process_str(exp)
    if @options.include?("--str")
      return s(:str, "STRING")
    else
      exp
    end
  end
  def process_lvar(exp)
    if @options.include?("--var")
      return s(:lvar, :var)
    else
      exp
    end
  end
  def process_iasgn(exp)
    if @options.include?("--var")
      exp[1] = :@var
      exp.each_index do |i|
        exp[i] = process(exp[i]) rescue exp[i]
      end   
      return exp
    else
      exp
    end
  end
  def process_lasgn(exp)
    if @options.include?("--var")    
      exp[1] = :var
      exp.each_index do |i|
        exp[i] = process(exp[i]) rescue exp[i]
      end   
      return exp
    else
      exp
    end
  end
  def process_dstr(exp)
    if @options.include?("--str")
      return s(:str, "STRING")
    else
      exp
    end
  end
  def process_defn(exp)
    if @options.include?("--fun")
      exp[1] = :function
    end
    exp.each_index do |i|
      exp[i] = process(exp[i]) rescue exp[i]
    end
    exp
  end
  def process_args(exp)
    if @options.include?("--fun")
      arg_size = exp.size - 1
      new_args = s(:args, :arglist)
      arg_size.times { new_args.push(:var)} unless @options.include?("--fargs")
      return new_args
    end
  end
  def process_cvar(exp)
    if @options.include?("--var")    
      s(:cvar, :@@var)
    else
      exp
    end
  end
  def process_ivar(exp)
    if @options.include?("--var")    
      s(:ivar, :@var)
    else
      exp
    end
  end
  def process_call(exp)
    blacklist = [:attr_accessor, :mattr_accessor, :autoload, :attr_reader, :require]
    if blacklist.include?(exp[2])
      # do nothing
    else
      @call_depth.push(1)
      exp.each_index do |i|
        exp[i] = process(exp[i]) rescue exp[i]
      end
      @call_depth.pop()
    end
    if @options.include?("--just-calls")
      @just_calls.push(Ruby2Ruby.new.process(exp.deep_copy).split("\n").map{|x| x.strip}.join("; ")) if @call_depth.size == 0
    end   
    return exp
  end
end

# Don't allow junk states
def reject(s1,s2,s3)
  bad_things = ["end", "", "#", "# end"]
  bad_things.include?(s1) || bad_things.include?(s2) || bad_things.include?(s3)
end

# Given a file and line, get the lines around it
def get_file_text(file,line,text)
  f_str = text.split("\n")
  sec_b = 3
  sec_e = DEPTH + 1
  s_l = (line > sec_b) ? line - sec_b : 0
  e_l = (line > f_str.size - sec_e - 1) ? f_str.size - 1 : line + sec_e
  subset = f_str[s_l..e_l]#.join("\n") rescue ""
  [file,line,subset,line-s_l]
end

# Build Markov model of length d
def build_table(seg,d,hsh,f)
  path = seg.split("\n").map{|x| x.strip }
  rest = path
  rest.each_index do |i|
    #hash_index = "hsh"
    if i < rest.size - (d - 1) && (!OPTIONS.include?("--junk") || (not reject(rest[i],rest[i+1],rest[i+2])))
      pattern_str = []
      (1..d).each {|j| pattern_str.push(rest[i+(j-1)])}
       
      lookup = Pattern.where(:pattern => pattern_str, :n => d)
      new_code = get_file_text(f,i,seg)
      new_proj = new_code[0].split("/")[1].split("_")[0]
      case lookup.size
      when 0
        bits = pattern_str.select{|x| x[0] != "#"}.join(" ").split(/ |\./).uniq.size * 100 / d
        Pattern.new({
          :pattern => pattern_str, 
          :n => d,
          :files => [new_code[0]],
          :count => 1, 
          :projects => [new_proj],
          :code => [new_code],
          :p_count => 1,
          :bits => bits
        }).save
      when 1
        old = lookup.first
        #only update if we haven't processed this before
        if !old.files.include?(new_code[0]) 
          new_projs = old.projects.push(new_proj).uniq
          lookup.update(
            :count => old.count + 1, 
            :files => old.files.push(new_code[0]).uniq, 
            :code =>  old.code.push(new_code),
            :projects => new_projs,
            :p_count => new_projs.size
          )
        end
      else
        throw "Something went wrong"
      end
              
      # (1..d).each {|j| hash_index += "[rest[#{i+(j-1)}]]"}
      # if eval(hash_index) == {}
      #   hash_index += "=[get_file_text(f,#{i},seg)]"
      #   eval(hash_index)
      # else
      #   hash_index += ".push(get_file_text(f,#{i},seg))"
      #   eval(hash_index)
      # end
    end
  end
end

# A really hacky way to flatten the table to relevent pieces
def rec_flatten(d,app,ks)
  if d > 0
    "table#{app}.keys.each {|k#{d}| "+rec_flatten(d-1,app+"[k#{d}]",ks.push("k#{d}"))+ "}"
  else
    "val = table#{app}; if val.size > 2; freqs.push([#{ks.join(',')},val.size,val]); end"
  end
end

table = InfinityHash.new
loc = 0

files.each do |f|
  begin
    orig_text = IO.read(f)
    exp = RubyParser.new.process(orig_text)
    ast_proc = FuncCalls.new(f,OPTIONS) 
    sexp = ast_proc.process(exp)

    #stats
    MYSTATS.loc = MYSTATS.loc + orig_text.split("\n").size
    MYSTATS.save
    
    if OPTIONS.include?("--range")
      (1..DEPTH).each do |d|
        if OPTIONS.include?("--just-calls")
          fcs = ast_proc.just_calls.join("\n")
          build_table(fcs,d,table,f)
        else
          text = Ruby2Ruby.new.process(sexp.deep_copy)
          build_table(text,d,table,f)
        end
      end
    else
      if OPTIONS.include?("--just-calls")
        fcs = ast_proc.just_calls.join("\n")
        build_table(fcs,DEPTH,table,f)
      else
        text = Ruby2Ruby.new.process(sexp.deep_copy)
        build_table(text,DEPTH,table,f)
      end
    end
    
  rescue
  end
end

# stats = {:loc => loc, :projects => projects, :options => OPTIONS}
# 
# # pp table
# 
# freqs = []
# eval(rec_flatten(DEPTH,"",[])) # magic assumes "freqs" and "table"
# freqs = freqs.sort_by {|x| x[DEPTH] * -1}
# 
# #pp freqs.map{|x| x.first(DEPTH)}
# puts Marshal.dump([stats,freqs])
