using Homebrew
using Base.Test

# Print some debugging info
println("Using Homebrew.jl installed to $(Homebrew.prefix())")

# Restore pkg-config to its installed (or non-installed) state at the end of all of this
pkg_was_installed = Homebrew.installed("pkg-config")

if pkg_was_installed
    info("Removing pkg-config for our testing...")
    Homebrew.rm("pkg-config")
end

# Add pkg-config
Homebrew.add("pkg-config")
@test Homebrew.installed("pkg-config") == true

# Now show that we have it
pkgconfig = Homebrew.info("pkg-config")
version_str = readchomp(`pkg-config --version`)
@test version_str == pkgconfig.version_str[1:length(version_str)]
@test Homebrew.installed(pkgconfig) == true
display(pkgconfig)
println(" installed to: $(Homebrew.prefix(pkgconfig))")

# Run through some of the Homebrew API, both with strings and with BrewPkg objects
@test length(filter(x -> x.name == "pkg-config", Homebrew.list())) > 0
@test Homebrew.linked("pkg-config") == true
@test Homebrew.linked(pkgconfig) == true

@test Homebrew.deps("pkg-config") == []
@test Homebrew.deps(pkgconfig) == []
@test Homebrew.deps("nettle") == [Homebrew.info("gmp")]
@test Homebrew.deps(Homebrew.info("nettle")) == [Homebrew.info("gmp")]

# Run through our sorted deps routines, ensuring that everything is sorted
sortdeps = Homebrew.deps_sorted("pango")
for idx in 1:length(sortdeps)
    for dep in Homebrew.deps(sortdeps[idx])
        depidx = findfirst(x -> (x.name == dep.name), sortdeps)
        @test depidx != 0
        @test depidx < idx
    end
end


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
    info("Adding pkg-config back again...")
    Homebrew.add("pkg-config")
end
