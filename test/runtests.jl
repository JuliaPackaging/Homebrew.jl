using Homebrew
using Base.Test

# Print some debugging info
info("Using Homebrew.jl installed to $(Homebrew.prefix())")

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
version = readchomp(`pkg-config --version`)
@test version == pkgconfig.version
@test Homebrew.installed(pkgconfig) == true
info("$(pkgconfig) installed to: $(Homebrew.prefix(pkgconfig))")

@test isdir(Homebrew.prefix("pkg-config"))
@test isdir(Homebrew.prefix(pkgconfig))

# Run through some of the Homebrew API, both with strings and with BrewPkg objects
@test length(filter(x -> x.name == "pkg-config", Homebrew.list())) > 0
@test Homebrew.linked("pkg-config") == true
@test Homebrew.linked(pkgconfig) == true

# Test dependency inspection
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

# Test that we can probe for bottles properly
@test Homebrew.has_bottle("ld64") == false
@test Homebrew.has_bottle("cairo") == true
@test Homebrew.has_relocatable_bottle("cairo") == false
@test Homebrew.has_relocatable_bottle("fontconfig") == true
@test Homebrew.json(pkgconfig)["name"] == "pkg-config"

# Test that we can translate properly
@test Homebrew.translate_formula("gettext"; verbose=true) == "staticfloat/juliatranslated/gettext"
@test Homebrew.translate_formula("ld64"; verbose=true) == "ld64"

# Make sure translation works properly with other taps
@test Homebrew.translate_formula("Homebrew/science/hdf5") == "staticfloat/juliatranslated/hdf5"
# Do it a second time so we can practice that bailing out
Homebrew.translate_formula("Homebrew/science/hdf5"; verbose=true)

# Test more miscellaneous things
@test Homebrew.formula_path("staticfloat/juliadeps/fontconfig") == joinpath(Homebrew.tappath, "fontconfig.rb")
@test !isempty(Homebrew.read_formula("xz"))
@test_throws ArgumentError Homebrew.add("thisisntapackagename")

Homebrew.unlink(pkgconfig)
@test Homebrew.installed(pkgconfig) == true
@test Homebrew.linked(pkgconfig) == false
Homebrew.link(pkgconfig)
@test Homebrew.installed(pkgconfig) == true
@test Homebrew.linked(pkgconfig) == true

# Can't really do anything useful with these, but can at least run them to ensure they work
Homebrew.outdated()
Homebrew.update()
Homebrew.postinstall("pkg-config")
Homebrew.postinstall(pkgconfig)
Homebrew.delete_translated_formula("gettext"; verbose=true)
Homebrew.delete_all_translated_formulae(verbose=true)

# Test deletion as well
Homebrew.rm(pkgconfig)
@test Homebrew.installed("pkg-config") == false
@test Homebrew.linked("pkg-config") == false

if pkg_was_installed
    info("Adding pkg-config back again...")
    Homebrew.add("pkg-config")
end
