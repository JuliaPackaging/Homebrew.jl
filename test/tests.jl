using Homebrew
using Base.Test

# Add pkg-config
Homebrew.add("pkg-config")

# Now show that we have it
run(`pkg-config --version`)
