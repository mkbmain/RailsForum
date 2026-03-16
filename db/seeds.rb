Provider.find_or_create_by!(id: 1) { |p| p.name = "google" }
Provider.find_or_create_by!(id: 2) { |p| p.name = "microsoft" }
Provider.find_or_create_by!(id: 3) { |p| p.name = "internal" }

puts "Seeded #{Provider.count} providers"

["Spam", "Harassment", "Against Guidelines"].each do |name|
  BanReason.find_or_create_by!(name: name)
end
puts "Seeded #{BanReason.count} ban reasons"

[
  [2, "Tech"],
  [3, "Life Style"],
  [4, "Off Topic"]
].each do |id, name|
  Category.find_or_create_by!(id: id) { |c| c.name = name }
end
puts "Seeded #{Category.count} categories"
