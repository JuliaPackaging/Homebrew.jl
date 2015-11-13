using Homebrew
using Base.Test

# Restore pkg-config to its installed (or non-installed) state at the end of all of this
pkg_was_installed = Homebrew.installed("pkg-config")

if pkg_was_installed
    Homebrew.rm("pkg-config")
end

# Add pkg-config
Homebrew.add("pkg-config")
@test Homebrew.installed("pkg-config") == true

# Now show that we have it
run(`pkg-config --version`)
pkgconfig = Homebrew.info("pkg-config")

# Run through some of the Homebrew API, both with strings and with BrewPkg objects
@test length(filter(x -> x.name == "pkg-config", Homebrew.list())) > 0
@test Homebrew.linked("pkg-config") == true
@test Homebrew.linked(pkgconfig) == true

# Can't really do anything useful with these, but can at least run them to ensure they work
Homebrew.outdated()
Homebrew.update()
Homebrew.postinstall("pkg-config")
Homebrew.postinstall(pkgconfig)

# Test deletion as well
Homebrew.rm(pkgconfig)
@test Homebrew.installed("pkg-config") == false
@test Homebrew.linked("pkg-config") == false

if pkg_was_installed
    Homebrew.add("pkg-config")
end
