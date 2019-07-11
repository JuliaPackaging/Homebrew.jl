using Homebrew
using Test

# Print some debugging info
@info("Using Homebrew.jl installed to $(Homebrew.prefix())")

# Restore pkg-config to its installed (or non-installed) state at the end of all of this
pkg_was_installed = Homebrew.installed("pkg-config")
libgfortran_was_installed = Homebrew.installed("staticfloat/juliadeps/libgfortran")

if pkg_was_installed
    @info("Removing pkg-config for our testing...")
    Homebrew.rm("pkg-config")
end

# Add pkg-config
Homebrew.add("pkg-config")
@test Homebrew.installed("pkg-config") == true

# Print versioninfo() to boost coverage
Homebrew.versioninfo()

# Now show that we have it and that it's the right version
function strip_underscores(str)
    range = something(findlast("_", str), 0:0)
    if range.start > 1
        return str[1:range.start-1]
    else
        return str
    end
end
pkgconfig = Homebrew.info("pkg-config")
version = readchomp(`pkg-config --version`)
@test version == strip_underscores(pkgconfig.version)
@test Homebrew.installed(pkgconfig) == true
@info("$(pkgconfig) installed to: $(Homebrew.prefix(pkgconfig))")

@test isdir(Homebrew.prefix("pkg-config"))
@test isdir(Homebrew.prefix(pkgconfig))

# Run through some of the Homebrew API, both with strings and with BrewPkg objects
@test length(filter(x -> x.name == "pkg-config", Homebrew.list())) > 0
@test Homebrew.linked("pkg-config") == true
@test Homebrew.linked(pkgconfig) == true

# Test dependency inspection
@test Homebrew.direct_deps("pkg-config") == []
@test Homebrew.direct_deps(pkgconfig) == []
@test Homebrew.direct_deps("nettle") == [Homebrew.info("gmp")]
@test Homebrew.direct_deps(Homebrew.info("nettle")) == [Homebrew.info("gmp")]

# Run through our sorted deps routines, ensuring that everything is sorted
sortdeps = Homebrew.deps_sorted("pango")
for idx in 1:length(sortdeps)
    for dep in Homebrew.direct_deps(sortdeps[idx])
        depidx = findfirst(x -> (x.name == dep.name), sortdeps)
        @test depidx != 0
        @test depidx < idx
    end
end

# Test that we can probe for bottles properly
@test Homebrew.has_bottle("ack") == false
@test Homebrew.has_bottle("cairo") == true
# I will be a very happy man the day this test starts to fail
@test Homebrew.has_relocatable_bottle("cairo") == false
if Homebrew.has_bottle("staticfloat/juliadeps/libgfortran")
    @test Homebrew.has_relocatable_bottle("staticfloat/juliadeps/libgfortran") == true
end
@test Homebrew.json(pkgconfig)["name"] == "pkg-config"

# Test that has_bottle knows which OSX version we're running on.
@test Homebrew.has_bottle("staticfloat/juliadeps/rmath-julia") == false

# Test that we can translate properly
@info("Translation should pass:")
@test Homebrew.translate_formula("gettext"; verbose=true) == "staticfloat/juliatranslated/gettext"
@info("Translation should fail because it has no bottles:")
@test Homebrew.translate_formula("ack"; verbose=true) == "ack"

if libgfortran_was_installed
    # Remove libgfortran before we start messing around with it
    Homebrew.rm("staticfloat/juliadeps/libgfortran"; force=true)
end

# Make sure translation works properly with other taps
Homebrew.delete_translated_formula("staticfloat/juliadeps/libgfortran"; verbose=true)
@info("Translation should pass because we just deleted libgfortran from translation cache:")
@test Homebrew.translate_formula("staticfloat/juliadeps/libgfortran"; verbose=true) == "staticfloat/juliatranslated/libgfortran"
@info("Translation should fail because libgfortran has already been translated:")
# Do it a second time so we can get coverage of practicing that particular method of bailing out
Homebrew.translate_formula(Homebrew.info("staticfloat/juliadeps/libgfortran"); verbose=true)

# Test that installation of a formula from a tap when it's already been translated works
Homebrew.add("staticfloat/juliadeps/libgfortran"; verbose=true)

if !libgfortran_was_installed
    Homebrew.rm("staticfloat/juliadeps/libgfortran")
end

# Now that we have staticfloat/juliadeps tapped, test to make sure that prefix() works
# with taps properly:
@test Homebrew.prefix("libgfortran") == Homebrew.prefix("staticfloat/juliadeps/libgfortran")

# Test more miscellaneous things
fontconfig = Homebrew.info("staticfloat/juliadeps/fontconfig")
@test Homebrew.formula_path(fontconfig) == joinpath(Homebrew.tappath, "fontconfig.rb")
@test !isempty(Homebrew.read_formula("xz"))
@test !isempty(Homebrew.read_formula(fontconfig))
@info("add() should fail because this actually isn't a package name:")
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

# Test deletion as well, showing that the array-argument form continues on after errors
Homebrew.rm(pkgconfig)
Homebrew.add(pkgconfig)
@info("rm() should fail because this isn't actually a package name:")
Homebrew.rm(["thisisntapackagename", "pkg-config"])
@test Homebrew.installed("pkg-config") == false
@test Homebrew.linked("pkg-config") == false

if pkg_was_installed
    @info("Adding pkg-config back again...")
    Homebrew.add("pkg-config")
end
