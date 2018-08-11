@static if Sys.isapple()
    using Homebrew
    Homebrew.update()
end
