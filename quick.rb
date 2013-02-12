(1..ARGV[0].to_i).each do |i|
  # `ruby markov.rb data/ #{i} --all-ast --junk > results/#{i}-all-junk`
  # `ruby markov.rb data/ #{i} --var --str --fun --fargs > results/#{i}-var-str`
  # `ruby markov.rb data/ #{i} --var --fun --fargs > results/#{i}-var`
  # `ruby markov.rb data/ #{i} --all-ast > results/#{i}-all`
  # `ruby markov.rb data/ #{i} --var --just-calls > results/#{i}-vall-calls`
  
  `ruby markov.rb data/ #{i} --all-ast`
  
end