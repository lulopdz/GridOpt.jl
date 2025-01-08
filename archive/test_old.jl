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
        [[246.5, 467.5], [290.0, 550.0]]
    ]
)

# Economic Parameters
a = [0.2, 0.1]                     # Amortization rate [%]
ρ = [
     [6000 2760], # T = 1, o = 1,2
     [6000 2760], # T = 2, o = 1,2
]                                       # Weight of operating condition o [h]
M = 1e10          # Big number


# # Economic Parameters
# a = [0.2, 0.1, 0.05]                     # Amortization rate [%]
# ρ = [
#      [3000 3000 2760], # T = 1, o = 1,2
#      [4000 2000 2760], # T = 2, o = 1,2
#      [2000 4000 2760]  # T = 3, o = 1,2
# ]                                       # Weight of operating condition o [h]

# demands = Dict(
#     :ID   => [1, 2],
#     :Node => [2, 4],
#     :Load => [
#         [[246.5, 357.0, 467.5], [261.0, 378.0, 495.0], [290.0, 420, 550.0]], 
#         [[150.0, 225.0, 300.0], [170.0, 255.0, 340.0], [200.0, 300, 400.0]] 
#     ]
# )


# Test with additional nodes, lines, and demands
# cand = Dict(
#     :ID         => [1, 2, 3],
#     :Node       => [2, 3, 4],
#     :Prod_cost  => [ # accross time
#         [25.0, 25.0, 25.0], 
#         [30.0, 30.0, 30.0], 
#         [20.0, 20.0, 20.0]
#     ], 
#     :Inv_cost   => [ # accross time
#         [700000, 700000, 700000], 
#         [800000, 800000, 800000], 
#         [700000, 700000, 700000]],
#     :Prod_cap   => [ # accross time
#         [[0 100 200 300 400], [0 100 200 300 400], [0 100 200 300 400]],
#         [[0 200 400 600 800], [0 200 400 600 800], [0 200 400 600 800]],
#         [[0 150 300 450 600], [0 150 300 450 600], [0 150 300 450 600]]
#     ]
# )

# exist = Dict(
#     :ID        => [1, 2],
#     :Node      => [1, 4],
#     :Max_cap   => [400, 500],
#     :Prod_cost => [ # accross time
#         [35.0, 35.0, 35.0], 
#         [32.0, 32.0, 32.0]
#         ]
# )

# lines = Dict(
#     :ID          => [1, 2, 3],
#     :From        => [1, 2, 3],
#     :To          => [2, 3, 4],
#     :Susceptance => [500.0, 400.0, 300.0],
#     :Capacity    => [200.0, 300.0, 250.0]
# )

# ==============================================================================
# Static single-node planning
# cand = Dict(
#     :ID         => [1, 2, 3],
#     :Prod_cost  => [25.0, 30.0, 20.0],
#     :Inv_cost   => [700000, 800000, 600000],
#     :Prod_cap   => [
#         [0 100 200 300 400],
#         [0 200 400 600 800],
#         [0 150 300 450 600]
#     ]
# )

# exist = Dict(
#     :ID        => [1, 2],
#     :Max_cap   => [400, 500],
#     :Prod_cost => [35.0, 32.0]
# )

# demands = Dict(
#     :ID   => [1, 2],
#     :Load => [
#         [290.0, 550.0],  
#         [200.0, 400.0] 
#     ]
# )

# ==============================================================================
# Dynamic single-node planning
# cand = Dict(
#     :ID         => [1, 2, 3],
#     :Prod_cost  => [[25.0, 25.0], [30.0, 30.0], [20.0, 20.0]],
#     :Inv_cost   => [[700000, 700000], [800000, 800000], [600000, 600000]],
#     :Prod_cap   => [
#         [[0 100 200 300 400], [0 100 200 300 400]],
#         [[0 200 400 600 800], [0 200 400 600 800]],
#         [[0 150 300 450 600], [0 150 300 450 600]]
#     ]
# )

# exist = Dict(
#     :ID        => [1, 2],
#     :Max_cap   => [400, 500],
#     :Prod_cost => [[35.0, 35.0], [32.0, 32.0]]
# )

# demands = Dict(
#     :ID   => [1, 2],
#     :Load => [
#         [[246.5, 467.5], [290.0, 550.0]], 
#         [[150.0, 300.0], [200.0, 400.0]] 
#     ]
# )

# ==============================================================================
# Static network constrained planning
# cand = Dict(
#     :ID         => [1, 2, 3],
#     :Node       => [2, 3, 4],
#     :Prod_cost  => [25.0, 30.0, 20.0],
#     :Inv_cost   => [700000, 800000, 600000],
#     :Prod_cap   => [
#         [0 100 200 300 400],
#         [0 200 400 600 800],
#         [0 150 300 450 600]
#     ]
# )

# exist = Dict(
#     :ID        => [1, 2],
#     :Node      => [1, 4],
#     :Max_cap   => [400, 500],
#     :Prod_cost => [35.0, 32.0]
# )

# lines = Dict(
#     :ID          => [1, 2, 3],
#     :From        => [1, 2, 3],
#     :To          => [2, 3, 4],
#     :Susceptance => [500.0, 400.0, 300.0],
#     :Capacity    => [200.0, 300.0, 250.0]
# )

# demands = Dict(
#     :ID   => [1, 2],
#     :Node => [2, 4],
#     :Load => [
#         [290.0, 550.0],  
#         [200.0, 400.0] 
#     ]
# )