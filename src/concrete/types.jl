# Configuration Structure
struct TEPConfig
    include_network::Bool      # true = multi-node network, false = single node
    use_integer::Bool          # true = binary investments, false = continuous relaxation
    per_unit::Bool             # true = per unit system, false = MW system
    bigM::Float64              # Big-M for candidate line constraints
    solver                     # Optimizer (e.g., GLPK.Optimizer)
end
