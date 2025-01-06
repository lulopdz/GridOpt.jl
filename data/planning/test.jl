# ==============================================================================
# Grid data full dynamic network planning

# Candidate generators data
cand = Dict(
    :ID         => [1],
    :Node       => [2],

    # Cost for each candidate generator in each time period
    :Prod_cost  => [
        [25.0, 25.0],
    ],

    :Inv_cost   => [
        [700000, 700000],
    ],

    :Prod_cap   => [
        [[0 100 200 300 400], [0 100 200 300 400]],
        [[0 100 200 300 400], [0 100 200 300 400]],
    ]
)

# Existing generators data
exist = Dict(
    :ID        => [1],
    :Node      => [1],
    :Max_cap   => [400],

    # Cost for each existing generator in each time period
    :Prod_cost => [
        [35.0, 35.0],
    ],   
)

# Transmission lines data
lines = Dict(
    :ID          => [1],              
    :From        => [1],              # Sending (from) node
    :To          => [2],              # Receiving (to) node
    :Susceptance => [500.0],          # Susceptance of transmission line [S]
    :Capacity    => [200.0],          # Capacity of transmission line [MW]
)

demands = Dict(
    :ID   => [1],
    :Node => [2],
    :Load => [
        [
            [246.5, 467.5],  # t=1 => o=1,2
            [290.0, 550.0]   # t=2 => o=1,2
        ]
    ]
)

# Economic Parameters
a = [0.2, 0.1]                     # Amortization rate [%]
ρ = [
     [6000 2760], # T = 1, o = 1,2
     [6000 2760], # T = 2, o = 1,2
]                                       # Weight of operating condition o [h]
M = 1e10          # Big number
