using Plots

# Function to set default plot settings
function set_plot_defaults()
    default(
        fontfamily = "lmsans17-regular",
        guidefont = font("lmsans17-regular", pointsize = 18.0),
        tickfont = font("lmsans17-regular", pointsize = 14.0),
        legendfont = font("lmsans17-regular", pointsize = 14.0),
        linewidth = 2,
        framestyle = :box,
        grid = true,
        size = (640, 480),
        dpi = 600
    )
end

# Function to save plots with a variable file extension
function save_plot(plot_object, filename, file_extension = ".pdf")
    Plots.savefig(plot_object, "$(filename)$(file_extension)")
end

# Colors
purple = "#9013FE"
blue = "#3182bd"
red = "#D0021B"
