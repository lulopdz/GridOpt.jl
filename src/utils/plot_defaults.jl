# src/plotting_style.jl
using Plots
using Measures

PLOT_COLORS = (
    purple = "#9013FE",
    blue   = "#3182bd",
    red    = "#D0021B",
    gray   = "#7F7F7F",
    green  = "#2ca25f",
    black  = "#636363",
)

function set_theme()
    default(
        fontfamily = "lmsans17-regular",
        guidefont  = font("lmsans17-regular", 10),
        tickfont   = font("lmsans17-regular", 9),
        legendfont = font("lmsans17-regular", 9),
        linewidth  = 2,
        framestyle = :box,
        grid       = true,
        # size       = (480, 480),
        size       = (480, 270), # 16:9 aspect ratio
        dpi        = 600,
        margin     = 2mm
    )
end

function latex_text(str, size=9, align=:center, color=:black)
    text(str, font("lmsans17-regular", size), align, color)
end