#hash_index = "hsh"
if i < rest.size - (d - 1) && (!OPTIONS.include?("--junk") || (not reject(rest[i],rest[i+1],rest[i+2])))
  # generate pattern key
  pattern_str = []
  (1..d).each {|j| pattern_str.push(rest[i+(j-1)])}
  #generate meta-data
  new_code = get_file_text(f,i,seg)
  new_proj = new_code[0].split("/")[1].split("_")[0]
  bits = pattern_str.select{|x| x[0] != "#"}.join(" ").split(/ |\./).uniq.size * 100 / d
  
  #assignment
  curr_data = hsh[pattern_str]
  if curr_data = {}
    hsh[pattern_str] = {
      :
    }
  
  hsh[pattern_str].push()
  lookup = Pattern.where(:n => d).where(:pattern => pattern_str)
