using LinearAlgebra
using DelimitedFiles
using Statistics
using LightGraphs
using SparseArrays
using CSV
using DataFrames
using IterTools
using PyCall
using Conda
using PyPlot

mutable struct QuantumState
    tableau::Matrix
    qubits::Int64

    QuantumState(qubits::Int64) = new(hcat(Matrix{Int64}(I,2*qubits,2*qubits),zeros(Int64,2*qubits,1)),qubits)
end 

function apply_h!(QS::QuantumState, qubit::Int64)
    for i = 1:2*QS.qubits
        QS.tableau[i,2*QS.qubits+1] = xor(QS.tableau[i,2*QS.qubits+1],QS.tableau[i,qubit]*QS.tableau[i,qubit+QS.qubits])
        QS.tableau[i,qubit], QS.tableau[i,qubit+QS.qubits] = QS.tableau[i,qubit+QS.qubits], QS.tableau[i,qubit]
    end
end

function apply_s!(QS::QuantumState, qubit::Int64)
    for i = 1:2*QS.qubits
        QS.tableau[i,2*QS.qubits+1] = xor(QS.tableau[i,2*QS.qubits+1],QS.tableau[i,qubit]*QS.tableau[i,qubit+QS.qubits])
        QS.tableau[i,qubit+QS.qubits] = xor(QS.tableau[i,qubit+QS.qubits], QS.tableau[i,qubit])
    end
end

function apply_cnot!(QS::QuantumState, control_qubit::Int64, target_qubit::Int64)
    for i = 1:2*QS.qubits
        QS.tableau[i,2*QS.qubits+1] = xor(QS.tableau[i,2*QS.qubits+1],QS.tableau[i,control_qubit]*QS.tableau[i,target_qubit+QS.qubits]*xor(QS.tableau[i,target_qubit],xor(QS.tableau[i,control_qubit+QS.qubits],1)))
        QS.tableau[i,target_qubit] = xor(QS.tableau[i,target_qubit],QS.tableau[i,control_qubit])
        QS.tableau[i,control_qubit+QS.qubits] = xor(QS.tableau[i,control_qubit+QS.qubits],QS.tableau[i,target_qubit+QS.qubits])
    end
end

function apply_z!(QS::QuantumState, qubit::Int64)
    apply_s!(QS, qubit)
    apply_s!(QS, qubit)
end

function apply_x!(QS::QuantumState, qubit::Int)
    apply_h!(QS, qubit)
    apply_z!(QS, qubit)
    apply_h!(QS, qubit)
end

function apply_y!(QS::QuantumState, qubit::Int64)
    apply_z!(QS, qubit)
    apply_x!(QS, qubit)
end

function apply_Rz!(QS::QuantumState, qubit::Int64)
    measurement = measure!(QS, qubit)
    if measurement != [1,0]
        apply_x!(QS, qubit)
    end
end

function func_g(x1::Int64,z1::Int64,x2::Int64,z2::Int64)
    if (x1 == 0) && (z1 == 0)
        return 0
    elseif (x1 == 1) && (z1 == 1)
        return z2 - x2
    elseif (x1 == 1) && (z1 == 0)
        return z2*(2*x2 - 1)
    else 
        return x2*(1 - 2*z2)
    end
end

function rowsum!(QS::QuantumState, h::Int64, i::Int64)
    value = 2*QS.tableau[h,2*QS.qubits+1] + 2*QS.tableau[i,2*QS.qubits+1]
    for j = 1:QS.qubits
        value += func_g(QS.tableau[i,j], QS.tableau[i,j+QS.qubits], QS.tableau[h,j], QS.tableau[h,j+QS.qubits])
    end

    if value%4 == 0
        QS.tableau[h,2*QS.qubits+1] = 0
    elseif value%4 == 2
        QS.tableau[h,2*QS.qubits+1] = 1
    end
    for j = 1:QS.qubits
        QS.tableau[h,j] = xor(QS.tableau[i,j],QS.tableau[h,j])
        QS.tableau[h,j+QS.qubits] = xor(QS.tableau[i,j+QS.qubits],QS.tableau[h,j+QS.qubits])
    end
end

function prob_measurement!(QS::QuantumState, qubit::Int64)
    is_random = false
    p::Int64 = 0
    for i = QS.qubits + 1:2*QS.qubits
        if QS.tableau[i,qubit] == 1
            is_random = true
            p = i
            break
        end
    end

    if is_random
        return [0.5,0.5,p]
    else
        QS.tableau = vcat(QS.tableau, zeros(Int64,1,2*QS.qubits+1))
        for i = 1:QS.qubits
            if QS.tableau[i,qubit] == 1
                rowsum!(QS,2*QS.qubits+1,i+QS.qubits)
            end
        end
        if QS.tableau[2*QS.qubits+1,2*QS.qubits+1] == 0
            QS.tableau = QS.tableau[1:2*QS.qubits,:]
            return [1,0]
        else
            QS.tableau = QS.tableau[1:2*QS.qubits,:]
            return [0,1]
        end
    end
end

function measure!(QS::QuantumState, qubit::Int64)
    prob_measure = prob_measurement!(QS, qubit)
    if prob_measure == [1,0]
        return +1
    elseif prob_measure == [0,1]
        return -1
    else
        for i = 1:2*QS.qubits
            if QS.tableau[i,qubit] == 1 & (i != Int64(prob_measure[3]))
                rowsum!(QS,i,Int64(prob_measure[3]))
            end
        end
        QS.tableau[Int64(prob_measure[3])-QS.qubits,:] = QS.tableau[Int64(prob_measure[3]),:]
        QS.tableau[Int64(prob_measure[3]),:] = zeros(Int64,1,2*QS.qubits+1)
        QS.tableau[Int64(prob_measure[3]),2*QS.qubits+1] = rand((0,1))
        QS.tableau[Int64(prob_measure[3]),QS.qubits+qubit] = 1
        if QS.tableau[Int64(prob_measure[3]),2*QS.qubits+1] == 0
            return +1
        elseif QS.tableau[Int64(prob_measure[3]),2*QS.qubits+1] == 1
            return -1
        end
    end
end

function oneNorm(vector::Array{Float64,1})
    one_norm_vector = 0.0
    for i in vector
        one_norm_vector += abs(i)
    end
    return one_norm_vector
end

function probDistribution(quasi_prob::Array{Float64,1})
    prob = zeros(0)
    cdf = zeros(1)
    quasi_prob_norm = oneNorm(quasi_prob)
    for i in quasi_prob
        append!(prob, abs(i)/quasi_prob_norm)
    end

    for i = 1:length(prob)
        append!(cdf,cdf[i]+prob[i])
    end
    return cdf
end

function samplingDistribution(cdf::Array{Float64,1})
    random_value = rand()
    idx = 0

    for i = 1:length(cdf)
        if random_value <= cdf[i]
            idx = i - 1
            break
        end
    end
    # display(idx)
    return idx
end

function generate_connections(n::Int64)
    d::Int64 = n
    dim::Int64 = 2*d - 1
    total_qubits::Int64 = dim*dim
    connections_dict = Dict{Int64,Array{Int64,1}}()
    for i = 1:total_qubits
        list_connections::Array{Int64,1} = []
        if i%dim == 0
            if i-dim > 0
                append!(list_connections,i-dim)
            end
            append!(list_connections,i-1)
            if i+dim < total_qubits + 1
                append!(list_connections,i+dim)
            end
        elseif i%dim == 1
            if i-dim > 0
                append!(list_connections,i-dim)
            end
            append!(list_connections,i+1)
            if i+dim < total_qubits+1
                append!(list_connections,i+dim)
            end
        else
            if i-dim > 0
                append!(list_connections,i-dim)
            end
            append!(list_connections,i-1)
            append!(list_connections,i+1)
            if i+dim < total_qubits+1
                append!(list_connections,i+dim)
            end
        end
        push!(connections_dict, i => list_connections)
    end
    return connections_dict
end

function generate_data_qubits(total_qubits::Int64)
    data_qubits::Array{Int64,1} = []
    for i = 1:total_qubits
        if i%2 != 0
            append!(data_qubits, i)
        end
    end
    return data_qubits
end

function generate_x_ancillas(d::Int64, total_qubits::Int64)
    x_ancillas::Array{Int64,1} = []
    for i = 1:d-1
        append!(x_ancillas, 2*i)
    end
    for j in x_ancillas
        if j + 4*d - 2 < total_qubits
            append!(x_ancillas, j + 4*d - 2)
        end
    end
    return x_ancillas
end

function generate_z_ancillas(d::Int64, total_qubits::Int64)
    z_ancillas::Array{Int64,1} = [2*d]
    for i = 1:d-1
        append!(z_ancillas, z_ancillas[end] + 2)
    end
    for j in z_ancillas
        if j + 4*d - 2  < total_qubits
            append!(z_ancillas, j + 4*d - 2)
        end
    end
    return z_ancillas
end

# function gateOperation!(QS::QuantumState, gate::Int64, qubit::Int64)
#     """Amplitude Damping"""
#     if gate == 2
#         apply_z!(QS, qubit)
#     elseif gate == 3
#         apply_Rz!(QS, qubit)
#     end
# end

function gateOperation!(QS::QuantumState, gate::Int64, qubit::Int64)
    """Pauli noise"""
    if gate == 2
        apply_x!(QS, qubit)
    elseif gate == 3
        apply_y!(QS, qubit)
    elseif gate == 4
        apply_z!(QS, qubit)
    end
end

function prep_x_ancillas!(QS::QuantumState, x_ancilla_list::Vector{Int64})
    for i in x_ancilla_list
        apply_h!(QS,i)
    end
end

function noisy_prep_x_ancillas!(QS::QuantumState, x_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for i in x_ancilla_list
        apply_h!(QS,i)
        display("prep")
        idx = samplingDistribution(cdf)
        display(idx)
        gateOperation!(QS, idx, i)
    end
end

function north_z_ancillas!(QS::QuantumState, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j-1 in graph[j]
            apply_cnot!(QS, j-1, j)
        end
    end
end

function noisy_north_z_ancillas!(QS::QuantumState, graph::Dict, z_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in z_ancilla_list
        if j-1 in graph[j]
            apply_cnot!(QS, j-1, j)
            display("northz")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j-1)
        end
    end
end

function north_x_ancillas!(QS::QuantumState, graph::Dict, x_ancilla_list::Vector{Int64})
    for j in x_ancilla_list
        if j-1 in graph[j]
            apply_cnot!(QS, j, j-1)
        end
    end
end

function noisy_north_x_ancillas!(QS::QuantumState, graph::Dict, x_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in x_ancilla_list
        if j-1 in graph[j]
            apply_cnot!(QS, j, j-1)
            display("northx")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j-1)
        end
    end
end

function west_z_ancillas!(QS::QuantumState, d::Int64, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j-(2*d-1) in graph[j]
            apply_cnot!(QS, j-(2*d-1), j)
        end
    end
end

function noisy_west_z_ancillas!(QS::QuantumState, d::Int64, graph::Dict, z_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in z_ancilla_list
        if j-(2*d-1) in graph[j]
            apply_cnot!(QS, j-(2*d-1), j)
            display("westz")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j-(2*d-1))
        end
    end
end

function west_x_ancillas!(QS::QuantumState, d::Int64, graph::Dict, x_ancilla_list::Vector{Int64})
    for j in x_ancilla_list
        if j-(2*d-1) in graph[j]
            apply_cnot!(QS, j, j-(2*d-1))
        end
    end
end

function noisy_west_x_ancillas!(QS::QuantumState, d::Int64, graph::Dict, x_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in x_ancilla_list
        if j-(2*d-1) in graph[j]
            apply_cnot!(QS, j, j-(2*d-1))
            display("westx")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j-(2*d-1))
        end
    end
end

function east_z_ancillas!(QS::QuantumState, d::Int64, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j+(2*d-1) in graph[j]
            apply_cnot!(QS, j+(2*d-1), j)
        end
    end
end

function noisy_east_z_ancillas!(QS::QuantumState, d::Int64, graph::Dict, z_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in z_ancilla_list
        if j+(2*d-1) in graph[j]
            apply_cnot!(QS, j+(2*d-1), j)
            display("eastz")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j+(2*d-1))
        end
    end
end

function east_x_ancillas!(QS::QuantumState, d::Int64, graph::Dict, x_ancilla_list::Vector{Int64})
    for j in x_ancilla_list
        if j+(2*d-1) in graph[j]
            apply_cnot!(QS, j, j+(2*d-1))
        end
    end
end

function noisy_east_x_ancillas!(QS::QuantumState, d::Int64, graph::Dict, x_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in x_ancilla_list
        if j+(2*d-1) in graph[j]
            apply_cnot!(QS, j, j+(2*d-1))
            display("eastx")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j+(2*d-1))
        end
    end
end

function south_z_ancillas!(QS::QuantumState, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j+1 in graph[j]
            apply_cnot!(QS, j+1, j)
        end
    end
end

function noisy_south_z_ancillas!(QS::QuantumState, graph::Dict, z_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in z_ancilla_list
        if j+1 in graph[j]
            apply_cnot!(QS, j+1, j)
            display("southz")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j+1)
        end
    end
end

function south_x_ancillas!(QS::QuantumState, graph::Dict, x_ancilla_list::Vector{Int64})
    for j in x_ancilla_list
        if j+1 in graph[j]
            apply_cnot!(QS, j, j+1)
        end
    end
end

function noisy_south_x_ancillas!(QS::QuantumState, graph::Dict, x_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    for j in x_ancilla_list
        if j+1 in graph[j]
            apply_cnot!(QS, j, j+1)
            display("southx")
            idx1 = samplingDistribution(cdf)
            idx2 = samplingDistribution(cdf)
            display(idx1)
            display(idx2)
            gateOperation!(QS, idx1, j)
            gateOperation!(QS, idx2, j+1)
        end
    end
end

function apply_noise!(QS::QuantumState, noise::Int64, qubit::Int64)
    if noise == 2
        apply_x!(QS, qubit)
    elseif noise == 3 
        apply_y!(QS, qubit)
    elseif noise == 4
        apply_z!(QS, qubit)
    elseif noise == 5
        apply_s!(QS, qubit)
    elseif noise == 6
        apply_Rz!(QS, qubit)
    end
end

function measurement_circuit!(QS::QuantumState, d::Int64, graph::Dict, 
    x_ancilla_list::Vector{Int64}, z_ancilla_list::Vector{Int64})
    # prepare the x_ancillas in the |+> state
    prep_x_ancillas!(QS, x_ancilla_list)

    # carry out the measurement circuits
    # North
    north_z_ancillas!(QS, graph, z_ancilla_list)

    north_x_ancillas!(QS, graph, x_ancilla_list)

    # West
    west_z_ancillas!(QS, d, graph, z_ancilla_list)

    west_x_ancillas!(QS, d, graph, x_ancilla_list)

    # East
    east_z_ancillas!(QS, d, graph, z_ancilla_list)

    east_x_ancillas!(QS, d, graph, x_ancilla_list)

    # South
    south_z_ancillas!(QS, graph, z_ancilla_list)

    south_x_ancillas!(QS, graph, x_ancilla_list) 

    # measurement of the x_ancillas is the x basis
    prep_x_ancillas!(QS, x_ancilla_list)
end

function noisy_measurement_circuit!(QS::QuantumState, d::Int64, graph::Dict, 
    x_ancilla_list::Vector{Int64}, z_ancilla_list::Vector{Int64}, cdf::Array{Float64,1})
    # prepare the x_ancillas in the |+> state
    noisy_prep_x_ancillas!(QS, x_ancilla_list, cdf)

    # carry out the measurement circuits
    # North
    noisy_north_z_ancillas!(QS, graph, z_ancilla_list, cdf)

    noisy_north_x_ancillas!(QS, graph, x_ancilla_list, cdf)

    # West
    noisy_west_z_ancillas!(QS, d, graph, z_ancilla_list, cdf)

    noisy_west_x_ancillas!(QS, d, graph, x_ancilla_list, cdf)

    # East
    noisy_east_z_ancillas!(QS, d, graph, z_ancilla_list, cdf)

    noisy_east_x_ancillas!(QS, d, graph, x_ancilla_list, cdf)

    # South
    noisy_south_z_ancillas!(QS, graph, z_ancilla_list, cdf)

    noisy_south_x_ancillas!(QS, graph, x_ancilla_list, cdf) 

    # measurement of the x_ancillas is the x basis
    noisy_prep_x_ancillas!(QS, x_ancilla_list, cdf)
end

function generate_fault_nodes(d::Int64, measurement_cycles::Array{Int64,2},
    x_ancilla_list::Vector{Int64}, z_ancilla_list::Vector{Int64})
    """
    Generates a list of nodes (vertex and plaquettes) with faults 
    numbered in the form of the volume lattice. Measurement cycles
    are measurement values for multiple cycles. 
    measurement_cycle[1]: initial values corresponding to +1
    measurement_cycle[2]: values of 1st cycle
    measurement_cycle[3]: values of 2nd cycle
    and so on ...
    """
    vertex_fault_list::Vector{Int64} = []
    for i = 1:size(measurement_cycles)[1]-1
        for j = 1:length(x_ancilla_list)
            if measurement_cycles[i,x_ancilla_list[j]]*measurement_cycles[i+1,x_ancilla_list[j]] == -1
                append!(vertex_fault_list, j+(i-1)*d*(d+1))
            end
        end
    end

    plaquette_fault_list::Vector{Int64} = []
    for i = 1:size(measurement_cycles)[1]-1
        for j = 1:length(z_ancilla_list)
            if measurement_cycles[i,z_ancilla_list[j]]*measurement_cycles[i+1,z_ancilla_list[j]] == -1
                append!(plaquette_fault_list, j+(i-1)*d*(d+1))
            end
        end
    end

    return vertex_fault_list, plaquette_fault_list
end

function ancilla_reset(QS::QuantumState, measurement::Vector{Int64})
    for j = 1:length(measurement)
        if measurement[j] == -1
            apply_x!(QS, j)
        end
    end
end

function generate_fault_graph(QS::QuantumState, d::Int64, graph::Dict, 
    x_ancilla_list::Vector{Int64}, z_ancilla_list::Vector{Int64},
    initial_measurement_values::Array{Int64,2})

    # initialize 

    which_ancilla::Vector{Int64} = [0,1]
    num_ancillas::UnitRange{Int64} = range(1, length = d*(d-1))
    x_depth::Vector{Int64} = [1,2,3,4,5,6]
    z_depth::Vector{Int64} = [2,3,4,5]
    error::Vector{Int64} = [1,2,3,4] # 1 -> I, 2 -> X, 3 -> Y, 4 -> Z 
    G_x = SimpleGraph(2*length(x_ancilla_list)+4*d)
    G_z = SimpleGraph(2*length(z_ancilla_list)+4*d)

    # noisy measurement circuit (enumerate through all possible single errors)
    for i in which_ancilla
        if i == 0
            # error in one of the x_ancilla circuits
            for j in num_ancillas
                # error during one of the 6 timesteps
                for k in x_depth
                    if k == 1
                        # noisy hadamard gate
                        for l in error
                            qs = deepcopy(QS)
                            measurement_cycle = deepcopy(initial_measurement_values)
                            # preparation measurement circuit
                            measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for preparation
                            for i in x_ancilla_list
                                measurement_cycle[1,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[1,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[1,:])
                            
                            prep_x_ancillas!(qs, x_ancilla_list)
                            apply_noise!(qs, l, x_ancilla_list[j])
                            # carry out the measurement circuits
                            north_z_ancillas!(qs, graph, z_ancilla_list)
                            north_x_ancillas!(qs, graph, x_ancilla_list)
                            west_z_ancillas!(qs, d, graph, z_ancilla_list)
                            west_x_ancillas!(qs, d, graph, x_ancilla_list)
                            east_z_ancillas!(qs, d, graph, z_ancilla_list)
                            east_x_ancillas!(qs, d, graph, x_ancilla_list)
                            south_z_ancillas!(qs, graph, z_ancilla_list)
                            south_x_ancillas!(qs, graph, x_ancilla_list) 
                            for m in x_ancilla_list
                                apply_h!(qs,m)
                            end
                            # ancilla measurement for cycle1
                            for i in x_ancilla_list
                                measurement_cycle[2,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[2,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[2,:])

                            # ideal measurement circuit
                            measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for cycle2
                            for i in x_ancilla_list
                                measurement_cycle[3,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[3,j] = measure!(qs,j)
                            end
                            edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                            if length(edges[1]) == 2
                                add_edge!(G_x, edges[1][1], edges[1][2])
                            end
                            if length(edges[2]) == 2
                                add_edge!(G_z, edges[2][1], edges[2][2])
                            end
                        end
                    elseif k == 2
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                if x_ancilla_list[j] - 1 in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] - 1)
                                end
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end
                    elseif k == 3 
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if x_ancilla_list[j] - (2*d - 1) in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] - (2*d - 1))
                                end
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end
                    elseif k == 4
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if x_ancilla_list[j] + (2*d - 1) in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] + (2*d - 1))
                                end
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end
                    elseif k == 5
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list)
                                if x_ancilla_list[j] + 1 in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] + 1)
                                end 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end
                    else
                        # noisy hadamard gate
                        for l in error
                            qs = deepcopy(QS)
                            measurement_cycle = deepcopy(initial_measurement_values)
                            # preparation measurement circuit
                            measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for preparation
                            for i in x_ancilla_list
                                measurement_cycle[1,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[1,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[1,:])

                            prep_x_ancillas!(qs, x_ancilla_list)
                            # carry out the measurement circuits
                            north_z_ancillas!(qs, graph, z_ancilla_list)
                            north_x_ancillas!(qs, graph, x_ancilla_list)
                            west_z_ancillas!(qs, d, graph, z_ancilla_list)
                            west_x_ancillas!(qs, d, graph, x_ancilla_list)
                            east_z_ancillas!(qs, d, graph, z_ancilla_list)
                            east_x_ancillas!(qs, d, graph, x_ancilla_list)
                            south_z_ancillas!(qs, graph, z_ancilla_list)
                            south_x_ancillas!(qs, graph, x_ancilla_list) 
                            for m in x_ancilla_list
                                apply_h!(qs,m)
                            end
                            apply_noise!(qs, l, x_ancilla_list[j])
                            # ancilla measurement for cycle1
                            for i in x_ancilla_list
                                measurement_cycle[2,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[2,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[2,:])

                            # ideal measurement circuit
                            measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for cycle2
                            for i in x_ancilla_list
                                measurement_cycle[3,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[3,j] = measure!(qs,j)
                            end
                            edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                            if length(edges[1]) == 2
                                add_edge!(G_x, edges[1][1], edges[1][2])
                            end
                            if length(edges[2]) == 2
                                add_edge!(G_z, edges[2][1], edges[2][2])
                            end
                        end
                    end
                end
            end
        else    
            # error in one of the z_ancilla circuits
            for j in num_ancillas
                # error during one of the 6 timesteps
                for k in z_depth
                    if k == 2
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                if z_ancilla_list[j] - 1 in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] - 1)
                                end
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end
                    elseif k == 3 
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if z_ancilla_list[j] - (2*d - 1) in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] - (2*d - 1))
                                end
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end
                    elseif k == 4
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if z_ancilla_list[j] + (2*d - 1) in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] + (2*d - 1))
                                end
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end
                    elseif k == 5
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(initial_measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list)
                                if z_ancilla_list[j] + 1 in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] + 1)
                                end 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                                if length(edges[1]) == 2
                                    add_edge!(G_x, edges[1][1], edges[1][2])
                                end
                                if length(edges[2]) == 2
                                    add_edge!(G_z, edges[2][1], edges[2][2])
                                end
                            end
                        end 
                    end
                end
            end
        end
    end

    for i in range(1, length = d)
        add_edge!(G_x, i, d*(d-1) + i)
        add_edge!(G_z, i, d*(d-1) + i)
    end

    for i in range(1+d*(d-2), length = d)
        add_edge!(G_x, i, i + 2*d)
        add_edge!(G_z, i, i + 2*d)
    end

    for i in range(1+d*(d+1), length = d)
        add_edge!(G_x, i, d*(d-1) + i)
        add_edge!(G_z, i, d*(d-1) + i)
    end

    for i in range(1+d*(d-2)+d*(d+1), length = d)
        add_edge!(G_x, i, i + 2*d)
        add_edge!(G_z, i, i + 2*d)
    end

    CSC_G_x = findnz(adjacency_matrix(G_x))
    CSC_G_z = findnz(adjacency_matrix(G_z))
    open("CSC_G_vertex1.txt", "w") do f
        for i = 1:length(CSC_G_x[1])
            println(f, (CSC_G_x[1][i], CSC_G_x[2][i]))
        end
    end

    open("CSC_G_plaquette1.txt", "w") do f
        for i = 1:length(CSC_G_z[1])
            println(f, (CSC_G_z[1][i], CSC_G_z[2][i]))
        end
    end

end

function distill_stabilizers(QS::QuantumState, d::Int64)
    """ This function finds the rows that corresponds to the uncoupled stabilizers. """

    total_qubits::Int64 = (2*d-1)^2
    stabilizers::Vector{Int64} = []

    for row = total_qubits+1:2*total_qubits
        isStab = false
        for i in findall(x -> x == 1, QS.tableau[row,1:total_qubits])
            if i%2 == 0 
                isStab = false 
                break
            else
                isStab = true
            end
        end
        if isStab == true 
            append!(stabilizers, QS.tableau[row,:])
        else
            for j in findall(x -> x == 1, QS.tableau[row,total_qubits + 1:2*total_qubits])
                if j%2 == 0
                    isStab = false 
                    break
                else
                    isStab = true
                end
            end
            if isStab == true 
                append!(stabilizers, QS.tableau[row,:])
            end
        end
    end
    final_stabilizers::Array{Int64,2} = transpose(reshape(stabilizers, (2*total_qubits+1, Int((total_qubits+1)/2))))
    I, J, V = findnz(sparse(final_stabilizers))
    df = DataFrame([:I => I, :J => J])
    CSV.write("spmatrix1.csv", df)

    return final_stabilizers
end

function commutation_check(stablilizers::Array{Int64,2}, d::Int64)
    """
    This function checks for commuting relationship between the X-logical operator
    and the uncoupled stabilizers. Returns the stabilizers that anti-commute with
    the X-logical operator. Then it takes the anti-commuting operators and recursively 
    eliminates all but one stabilizer that anti-commutes with the X-logical operator 
    and this stabilizer is the one that stores the state of the surface code.
    """
    total_qubits::Int64 = (2*d-1)^2
    anti_comm_stabilizer::Vector{Int64} = []
    x_logical::Vector{Int64} = zeros(Int64, 2*total_qubits + 1)
    for i = 1:d
        x_logical[1+2*(2*d-1)*(i-1)] = 1
    end
    for i = 1:size(stablilizers)[1]
        if length(findall(x -> x == 1, 
            x_logical[1:total_qubits].*stablilizers[i,total_qubits+1:2*total_qubits]))%2 == 1
            append!(anti_comm_stabilizer, stablilizers[i,:])
        end
    end
    remaining_stabilizers::Array{Int64,2} = transpose(reshape(anti_comm_stabilizer, 
    (2*total_qubits+1, Int(length(anti_comm_stabilizer)/(2*total_qubits+1)))))

    for i = 1:size(remaining_stabilizers)[1]-1
        remaining_stabilizers[i,:] = xor.(remaining_stabilizers[i,:],remaining_stabilizers[i+1,:])
    end    

    return remaining_stabilizers[end,end]
end

# Recovery Section
function find_data_qubit_z(d::Int64, surface_code_lattice::Dict, x_ancilla_list::Vector{Int64}, 
    fault_edge::Vector{Int64})

    data_qubits::Vector{Int64} = []
    for node = 1:length(fault_edge)-1
        if abs(x_ancilla_list[fault_edge[1]]-x_ancilla_list[fault_edge[2]]) == 2*(2*d-1) - 2
            append!(data_qubits, intersect(surface_code_lattice[x_ancilla_list[min(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[x_ancilla_list[min(fault_edge[node], fault_edge[node+1])+d-1]]))
            append!(data_qubits, intersect(surface_code_lattice[x_ancilla_list[max(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[x_ancilla_list[max(fault_edge[node], fault_edge[node+1])+1]]))
        elseif abs(x_ancilla_list[fault_edge[1]]-x_ancilla_list[fault_edge[2]]) == 2*(2*d-1) + 2
            append!(data_qubits, intersect(surface_code_lattice[x_ancilla_list[max(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[x_ancilla_list[max(fault_edge[node], fault_edge[node+1])-d+1]]))
            append!(data_qubits, intersect(surface_code_lattice[x_ancilla_list[min(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[x_ancilla_list[min(fault_edge[node], fault_edge[node+1])+1]]))
        else
            append!(data_qubits, intersect(surface_code_lattice[x_ancilla_list[fault_edge[node]]],
            surface_code_lattice[x_ancilla_list[fault_edge[node+1]]]))
        end
    end
    return data_qubits
end

function find_data_qubit_x(d::Int64, surface_code_lattice::Dict, z_ancilla_list::Vector{Int64}, 
    fault_edge::Vector{Int64})

    data_qubits::Vector{Int64} = []
    for node = 1:length(fault_edge)-1
        if abs(z_ancilla_list[fault_edge[1]]-z_ancilla_list[fault_edge[2]]) == 2*(2*d-1) - 2
            append!(data_qubits, intersect(surface_code_lattice[z_ancilla_list[min(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[z_ancilla_list[min(fault_edge[node], fault_edge[node+1])+d]]))
            append!(data_qubits, intersect(surface_code_lattice[z_ancilla_list[max(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[z_ancilla_list[max(fault_edge[node], fault_edge[node+1])+1]]))
        elseif abs(z_ancilla_list[fault_edge[1]]-z_ancilla_list[fault_edge[2]]) == 2*(2*d-1) + 2
            append!(data_qubits, intersect(surface_code_lattice[z_ancilla_list[max(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[z_ancilla_list[max(fault_edge[node], fault_edge[node+1])-d]]))
            append!(data_qubits, intersect(surface_code_lattice[z_ancilla_list[min(fault_edge[node], fault_edge[node+1])]],
            surface_code_lattice[z_ancilla_list[min(fault_edge[node], fault_edge[node+1])+1]]))
        else
            append!(data_qubits, intersect(surface_code_lattice[z_ancilla_list[fault_edge[node]]],
            surface_code_lattice[z_ancilla_list[fault_edge[node+1]]]))
        end
    end
    return data_qubits
end

function find_x_error_qubits(d::Int64, surface_code_lattice::Dict, z_ancilla_list::Vector{Int64}, 
    z_edge_list::Array{Tuple{Int64,Int64,Array{Int64,1}},1}, ghost_nodes::Vector{Int64})

    x_error_qubits::Vector{Int64} = [] # qubits where x error occurred 

    for edge in z_edge_list
        if (edge[1] in ghost_nodes)
            if (edge[2] in ghost_nodes)
                # both ghost nodes: do nothing
            else
                # one ghost and one real: find corresponding data qubit
                if (edge[1] - edge[2]) % (d*(d+1)) == 0
                    # real node with temporal ghost node: do nothing
                else
                    if z_ancilla_list[edge[2]-floor(Int64, edge[2]/(d*(d+1)))*d*(d+1)] < ((2*d-1)^2)/2
                        data_qubit = z_ancilla_list[edge[2]-floor(Int64, edge[2]/(d*(d+1)))*d*(d+1)] - (2*d-1)
                        while data_qubit > 0
                            append!(x_error_qubits, data_qubit)
                            data_qubit -= 2*(2*d-1)
                        end
                    else
                        data_qubit = z_ancilla_list[edge[2]-floor(Int64, edge[2]/(d*(d+1)))*d*(d+1)] + (2*d-1)
                        while data_qubit <= ((2*d-1)^2)
                            append!(x_error_qubits, data_qubit)
                            data_qubit += 2*(2*d-1)
                        end
                    end
                end
            end
        else
            if (edge[2] in ghost_nodes)
                # one ghost and one real: find corresponding data qubit 
                if (edge[2] - edge[1]) % (d*(d+1)) == 0
                    # real node with temporal ghost node: do nothing
                else
                    if z_ancilla_list[edge[1]-floor(Int64, edge[1]/(d*(d+1)))*d*(d+1)] < ((2*d-1)^2)/2
                        data_qubit = z_ancilla_list[edge[1]-floor(Int64, edge[1]/(d*(d+1)))*d*(d+1)] - (2*d-1)
                        while data_qubit > 0
                            append!(x_error_qubits, data_qubit)
                            data_qubit -= 2*(2*d-1)
                        end
                    else
                        data_qubit = z_ancilla_list[edge[1]-floor(Int64, edge[1]/(d*(d+1)))*d*(d+1)] + (2*d-1)
                        while data_qubit <= ((2*d-1)^2)
                            append!(x_error_qubits, data_qubit)
                            data_qubit += 2*(2*d-1)
                        end
                    end
                end
            else
                if edge[2] == edge[1] + d*(d+1) || edge[2] == edge[1] - d*(d+1)
                    # error on ancilla qubit: do nothing
                else
                    # Fault on a data qubit: find the corresponding qubit at t=0
                    fault_edge::Vector{Int64} = [i - floor(Int64, i/(d*(d+1)))*d*(d+1) for i in edge[3]]
                    append!(x_error_qubits, find_data_qubit_x(d, surface_code_lattice, z_ancilla_list,
                    fault_edge))
                end
            end
        end
    end
    return x_error_qubits
end

function find_z_error_qubits(d::Int64, surface_code_lattice::Dict, x_ancilla_list::Vector{Int64}, 
    x_edge_list::Array{Tuple{Int64,Int64,Array{Int64,1}},1}, ghost_nodes::Vector{Int64})

    z_error_qubits::Vector{Int64} = [] # qubits where z error occurred
    
    for edge in x_edge_list
        if (edge[1] in ghost_nodes)
            if (edge[2] in ghost_nodes)
                # both ghost nodes: do nothing
            else
                # one ghost and one real: find corresponding data qubit 
                if (edge[1] - edge[2]) % (d*(d+1)) == 0
                    # real node with temporal ghost node: do nothing
                else
                    if x_ancilla_list[edge[2]-floor(Int64, edge[2]/(d*(d+1)))*d*(d+1)] % (2*d-1) < d
                        data_qubit = x_ancilla_list[edge[2]-floor(Int64, edge[2]/(d*(d+1)))*d*(d+1)] - 1
                        while data_qubit > 0 && data_qubit % (2*d-1) < d
                            append!(z_error_qubits, data_qubit)
                            data_qubit -= 2
                        end
                    else
                        data_qubit = x_ancilla_list[edge[2]-floor(Int64, edge[2]/(d*(d+1)))*d*(d+1)] + 1
                        while (data_qubit <= (2*d-1)^2) && (data_qubit % (2*d-1) > d || data_qubit % (2*d-1) == 0)
                            append!(z_error_qubits, data_qubit)
                            data_qubit += 2
                        end
                    end
                end
            end
        else
            if (edge[2] in ghost_nodes)
                # one ghost and one real: find corresponding data qubit 
                if (edge[2] - edge[1]) % (d*(d+1)) == 0
                    # real node with temporal ghost node: do nothing
                else
                    if x_ancilla_list[edge[1]-floor(Int64, edge[1]/(d*(d+1)))*d*(d+1)] % (2*d-1) < d
                        data_qubit = x_ancilla_list[edge[1]-floor(Int64, edge[1]/(d*(d+1)))*d*(d+1)] - 1
                        while data_qubit > 0 && data_qubit % (2*d-1) < d
                            append!(z_error_qubits, data_qubit)
                            data_qubit -= 2
                        end
                    else
                        data_qubit = x_ancilla_list[edge[1]-floor(Int64, edge[1]/(d*(d+1)))*d*(d+1)] + 1
                        while (data_qubit <= (2*d-1)^2) && (data_qubit % (2*d-1) > d || data_qubit % (2*d-1) == 0)
                            append!(z_error_qubits, data_qubit)
                            data_qubit += 2
                        end
                    end
                end
            else
                if edge[2] == edge[1] + d*(d+1) || edge[2] == edge[1] - d*(d+1)
                    # error on ancilla qubit: do nothing
                else
                    # Fault on a data qubit: find the corresponding qubit at t=0
                    fault_edge::Vector{Int64} = [i - floor(Int64, i/(d*(d+1)))*d*(d+1) for i in edge[3]]
                    append!(z_error_qubits, find_data_qubit_z(d, surface_code_lattice, x_ancilla_list,
                    fault_edge))
                end
            end
        end
    end
    return z_error_qubits
end

function apply_recovery(QS::QuantumState, x_error_qubits::Vector{Int64}, z_error_qubits::Vector{Int64})
    for i in x_error_qubits
        apply_x!(QS, i)
    end
    for i in z_error_qubits
        apply_z!(QS, i)
    end
end

function main(d::Int64, noise::Float64)
    # initialize values and get the connections between qubits. 
    total_qubits::Int64 = (2*d-1)^2
    QS = QuantumState(total_qubits)
    connections::Dict = generate_connections(d)
    measurement_values::Array{Int64,2} = zeros(Int64, (d+1, total_qubits))
    final_measurement_values::Array{Int64,2} = zeros(Int64, (2, total_qubits))
    last_measurement::Array{Int64,2} = zeros(Int64, (2, total_qubits))

    # generate the different sets of qubits
    data_qubits_list::Vector{Int64} = generate_data_qubits(total_qubits)
    x_ancilla_list::Vector{Int64} = generate_x_ancillas(d, total_qubits)
    z_ancilla_list::Vector{Int64} = generate_z_ancillas(d, total_qubits)

    ghost_nodes::Vector{Int64} = [0]
    for i = 1:d
        append!(ghost_nodes, range((i-1)*d*(d+1) + d*(d-1) + 1, i*d*(d+1), step=1))
    end
    append!(ghost_nodes, range(d*d*(d+1)+1, d*d*(d+1)+d*(d-1), step=1))

    # One round of ideal measurement circuit for preparation of ancillas
    measurement_circuit!(QS, d, connections, x_ancilla_list, z_ancilla_list) 
    for i in x_ancilla_list
        measurement_values[1,i] = measure!(QS, i)
    end

    for i in z_ancilla_list
        measurement_values[1,i] = measure!(QS, i)
    end
    
    ancilla_reset(QS, measurement_values[1,:])

    # Find the logical state of the surface code
    initial_code_state::Int64 = commutation_check(distill_stabilizers(deepcopy(QS), d), d)

    # Quasi-probability distribution -> cumulative density function
    quasi_prob::Vector{Float64} = [1-noise, noise/3, noise/3, noise/3]
    cdf::Array{Float64,1} = probDistribution(quasi_prob)

    """
    Checking of each possible error and the final logical state.
    """
    # initialize 

    which_ancilla::Vector{Int64} = [0,1]
    num_ancillas::UnitRange{Int64} = range(1, length = d*(d-1))
    x_depth::Vector{Int64} = [1,2,3,4,5,6]
    z_depth::Vector{Int64} = [2,3,4,5]
    error::Vector{Int64} = [1,2,3,4] # 1 -> I, 2 -> X, 3 -> Y, 4 -> Z 
    graph = connections

    # noisy measurement circuit (enumerate through all possible single errors)
    # for i in which_ancilla
    for i = 0:0
        if i == 0
            # error in one of the x_ancilla circuits
            for j in num_ancillas
                # error during one of the 6 timesteps
                # for k in x_depth
                for k = 1:1
                    if k == 1
                        # noisy hadamard gate
                        for l in error
                            qs = deepcopy(QS)
                            measurement_cycle = deepcopy(measurement_values)
                            # preparation measurement circuit
                            measurement_circuit!(qs, d, connections, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for preparation
                            for i in x_ancilla_list
                                measurement_cycle[1,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[1,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[1,:])
                            
                            prep_x_ancillas!(qs, x_ancilla_list)
                            apply_noise!(qs, l, x_ancilla_list[j])
                            # carry out the measurement circuits
                            north_z_ancillas!(qs, graph, z_ancilla_list)
                            north_x_ancillas!(qs, graph, x_ancilla_list)
                            west_z_ancillas!(qs, d, graph, z_ancilla_list)
                            west_x_ancillas!(qs, d, graph, x_ancilla_list)
                            east_z_ancillas!(qs, d, graph, z_ancilla_list)
                            east_x_ancillas!(qs, d, graph, x_ancilla_list)
                            south_z_ancillas!(qs, graph, z_ancilla_list)
                            south_x_ancillas!(qs, graph, x_ancilla_list) 
                            for m in x_ancilla_list
                                apply_h!(qs,m)
                            end
                            # ancilla measurement for cycle1
                            for i in x_ancilla_list
                                measurement_cycle[2,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[2,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[2,:])

                            # ideal measurement circuit
                            measurement_circuit!(qs, d, connections, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for cycle2
                            for i in x_ancilla_list
                                measurement_cycle[3,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[3,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[3,:])

                            # ideal measurement circuit
                            measurement_circuit!(qs, d, connections, x_ancilla_list, z_ancilla_list)
                            
                            for i in x_ancilla_list
                                measurement_cycle[4,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[4,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[3,:])

                            # ideal measurement circuit
                            measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for cycle2
                            for i in x_ancilla_list
                                measurement_cycle[4,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[4,j] = measure!(qs,j)
                            end
                            
                            ancilla_reset(qs, measurement_cycle[4,:])

                            fault_list = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                            display("Fault")
                            display(fault_list)

                            # Find the most likely faults by using the shortest path and minimum weight matching algorithms
                            pushfirst!(PyVector(pyimport("sys")."path"), "")
                            fault_search = pyimport("fault_search")
                            fault_edges_vertex = fault_search.noisy_recovery("CSC_G_vertex.txt", d, d+1, fault_list[1], 100)
                            fault_edges_plaquette = fault_search.noisy_recovery("CSC_G_plaquette.txt", d, d+1, fault_list[2], 100)
                            
                            display("Matching")
                            display(fault_edges_plaquette)
                            display(fault_edges_vertex)
                            display(measurement_cycle)
                            error_x::Vector{Int64} = []
                            error_z::Vector{Int64} = []
                            # # # Use the fault edges to find the qubits where the errors have occurred and apply recovery 
                            if isempty(fault_edges_plaquette) == false
                                append!(error_x, find_x_error_qubits(d, connections, z_ancilla_list, fault_edges_plaquette, ghost_nodes))
                            end

                            if isempty(fault_edges_vertex) == false
                                append!(error_z, find_z_error_qubits(d, connections, x_ancilla_list, fault_edges_vertex, ghost_nodes))
                            end

                            display("Error")
                            display(error_x)
                            display(error_z)
                            apply_recovery(qs, error_x, error_z)
                            measurement_circuit!(qs, d, connections, x_ancilla_list, z_ancilla_list) 
                            for i in x_ancilla_list
                                final_measurement_values[2,i] = measure!(qs, i)
                            end

                            for i in z_ancilla_list
                                final_measurement_values[2,i] = measure!(qs, i)
                            end
                            
                            for i = 1:total_qubits
                                final_measurement_values[1,i] = measurement_cycle[1,i]
                                last_measurement[1,i] = measurement_cycle[1,i]
                            end

                            display(final_measurement_values)
                            # Generate faults from the measurement value of initial and final cycle. Tuple containing x and z ancilla
                            final_fault_list = generate_fault_nodes(d, final_measurement_values, x_ancilla_list, z_ancilla_list)
                            display("Fault")
                            display(final_fault_list)

                            # Find the most likely faults by using the shortest path and minimum weight matching algorithms
                            pushfirst!(PyVector(pyimport("sys")."path"), "")
                            fault_search = pyimport("fault_search")
                            fault_edges_vertex = fault_search.ideal_recovery("CSC_G_vertex.txt", d, final_fault_list[1], 100)
                            fault_edges_plaquette = fault_search.ideal_recovery("CSC_G_plaquette.txt", d, final_fault_list[2], 100)
                            display("Matching")
                            display(fault_edges_plaquette)
                            display(fault_edges_vertex)

                            final_error_x::Vector{Int64} = []
                            final_error_z::Vector{Int64} = []
                            # Use the fault edges to find the qubits where the errors have occurred and apply recovery 
                            if isempty(fault_edges_plaquette) == false
                                append!(final_error_x, find_x_error_qubits(d, connections, z_ancilla_list, fault_edges_plaquette, ghost_nodes))
                            end

                            if isempty(fault_edges_vertex) == false
                                append!(final_error_z, find_z_error_qubits(d, connections, x_ancilla_list, fault_edges_vertex, ghost_nodes))
                            end

                            display("Error")
                            display(final_error_x)
                            display(final_error_z)
                            apply_recovery(qs, final_error_x, final_error_z)
                            ancilla_reset(qs, final_measurement_values[2,:])
                            measurement_circuit!(qs, d, connections, x_ancilla_list, z_ancilla_list) 
                            for i in x_ancilla_list
                                last_measurement[2,i] = measure!(qs, i)
                            end

                            for i in z_ancilla_list
                                last_measurement[2,i] = measure!(qs, i)
                            end
                            display(last_measurement)
                            final_code_state::Int64 = commutation_check(distill_stabilizers(deepcopy(qs), d), d)
                            display(final_code_state)
                            if final_code_state == 1
                                return "Logical Error"
                            end
                        end
                    elseif k == 2
                        for l in error
                            for m = 1:1
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                if x_ancilla_list[j] - 1 in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] - 1)
                                end
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                            end
                        end
                    elseif k == 3 
                        for l in error
                            for m = 1:1
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if x_ancilla_list[j] - (2*d - 1) in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] - (2*d - 1))
                                end
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                ancilla_reset(qs, measurement_cycle[3,:])
                                
                            end
                        end
                    elseif k == 4
                        for l in error
                            for m = 1:1
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if x_ancilla_list[j] + (2*d - 1) in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] + (2*d - 1))
                                end
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                            end
                        end
                    elseif k == 5
                        for l = 1:1
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list)
                                if x_ancilla_list[j] + 1 in graph[x_ancilla_list[j]]
                                    apply_noise!(qs, l, x_ancilla_list[j])
                                    apply_noise!(qs, m, x_ancilla_list[j] + 1)
                                end 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                            end
                        end
                    else
                        # noisy hadamard gate
                        for l in error
                            qs = deepcopy(QS)
                            measurement_cycle = deepcopy(measurement_values)
                            # preparation measurement circuit
                            measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for preparation
                            for i in x_ancilla_list
                                measurement_cycle[1,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[1,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[1,:])

                            prep_x_ancillas!(qs, x_ancilla_list)
                            # carry out the measurement circuits
                            north_z_ancillas!(qs, graph, z_ancilla_list)
                            north_x_ancillas!(qs, graph, x_ancilla_list)
                            west_z_ancillas!(qs, d, graph, z_ancilla_list)
                            west_x_ancillas!(qs, d, graph, x_ancilla_list)
                            east_z_ancillas!(qs, d, graph, z_ancilla_list)
                            east_x_ancillas!(qs, d, graph, x_ancilla_list)
                            south_z_ancillas!(qs, graph, z_ancilla_list)
                            south_x_ancillas!(qs, graph, x_ancilla_list) 
                            for m in x_ancilla_list
                                apply_h!(qs,m)
                            end
                            apply_noise!(qs, l, x_ancilla_list[j])
                            # ancilla measurement for cycle1
                            for i in x_ancilla_list
                                measurement_cycle[2,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[2,j] = measure!(qs,j)
                            end

                            ancilla_reset(qs, measurement_cycle[2,:])

                            # ideal measurement circuit
                            measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                            # ancilla measurement for cycle2
                            for i in x_ancilla_list
                                measurement_cycle[3,i] = measure!(qs,i)
                            end

                            for j in z_ancilla_list
                                measurement_cycle[3,j] = measure!(qs,j)
                            end
                        end
                    end
                end
            end
        else    
            # error in one of the z_ancilla circuits
            for j in num_ancillas
                # error during one of the 6 timesteps
                for k in z_depth
                    if k == 2
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                if z_ancilla_list[j] - 1 in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] - 1)
                                end
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                            end
                        end
                    elseif k == 3 
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if z_ancilla_list[j] - (2*d - 1) in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] - (2*d - 1))
                                end
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                            end
                        end
                    elseif k == 4
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                if z_ancilla_list[j] + (2*d - 1) in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] + (2*d - 1))
                                end
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list) 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                            end
                        end
                    elseif k == 5
                        for l in error
                            for m in error
                                qs = deepcopy(QS)
                                measurement_cycle = deepcopy(measurement_values)
                                # preparation measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for preparation
                                for i in x_ancilla_list
                                    measurement_cycle[1,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[1,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[1,:])

                                prep_x_ancillas!(qs, x_ancilla_list)
                                # carry out the measurement circuits
                                north_z_ancillas!(qs, graph, z_ancilla_list)
                                north_x_ancillas!(qs, graph, x_ancilla_list)
                                west_z_ancillas!(qs, d, graph, z_ancilla_list)
                                west_x_ancillas!(qs, d, graph, x_ancilla_list)
                                east_z_ancillas!(qs, d, graph, z_ancilla_list)
                                east_x_ancillas!(qs, d, graph, x_ancilla_list)
                                south_z_ancillas!(qs, graph, z_ancilla_list)
                                south_x_ancillas!(qs, graph, x_ancilla_list)
                                if z_ancilla_list[j] + 1 in graph[z_ancilla_list[j]]
                                    apply_noise!(qs, l, z_ancilla_list[j])
                                    apply_noise!(qs, m, z_ancilla_list[j] + 1)
                                end 
                                for m in x_ancilla_list
                                    apply_h!(qs,m)
                                end
                                # ancilla measurement for cycle1
                                for i in x_ancilla_list
                                    measurement_cycle[2,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[2,j] = measure!(qs,j)
                                end

                                ancilla_reset(qs, measurement_cycle[2,:])

                                # ideal measurement circuit
                                measurement_circuit!(qs, d, graph, x_ancilla_list, z_ancilla_list)

                                # ancilla measurement for cycle2
                                for i in x_ancilla_list
                                    measurement_cycle[3,i] = measure!(qs,i)
                                end

                                for j in z_ancilla_list
                                    measurement_cycle[3,j] = measure!(qs,j)
                                end
                                edges = generate_fault_nodes(d, measurement_cycle, x_ancilla_list, z_ancilla_list)
                            end
                        end 
                    end
                end
            end
        end
    end

    #=

    # Collect the measurement values for d cycles
    for j = 1:d
        measurement_circuit!(QS, d, connections, x_ancilla_list, z_ancilla_list)
        for i in x_ancilla_list
            measurement_values[j+1,i] = measure!(QS, i)
        end
    
        for i in z_ancilla_list
            measurement_values[j+1,i] = measure!(QS, i)
        end

        ancilla_reset(QS, measurement_values[j+1,:])
    end

    # # Only run the below function once to generate the initial error lattice
    # generate_fault_graph(QS, d, connections, x_ancilla_list, z_ancilla_list, 
    # zeros(Int64, (d, total_qubits)))

    # # Generate faults from the measurement values of d cycles. Tuple containing x and z ancilla
    fault_list = generate_fault_nodes(d, measurement_values, x_ancilla_list, z_ancilla_list)
    display("Fault")
    display(fault_list)

    # Find the most likely faults by using the shortest path and minimum weight matching algorithms
    pushfirst!(PyVector(pyimport("sys")."path"), "")
    fault_search = pyimport("fault_search")
    fault_edges_vertex = fault_search.noisy_recovery("CSC_G_vertex.txt", d, d+1, fault_list[1], 100)
    fault_edges_plaquette = fault_search.noisy_recovery("CSC_G_plaquette.txt", d, d+1, fault_list[2], 100)
    
    display("Matching")
    display(fault_edges_plaquette)
    display(fault_edges_vertex)

    error_x::Vector{Int64} = []
    error_z::Vector{Int64} = []
    # # # Use the fault edges to find the qubits where the errors have occurred and apply recovery 
    if isempty(fault_edges_plaquette) == false
        append!(error_x, find_x_error_qubits(d, connections, z_ancilla_list, fault_edges_plaquette, ghost_nodes))
    end

    if isempty(fault_edges_vertex) == false
        append!(error_z, find_z_error_qubits(d, connections, x_ancilla_list, fault_edges_vertex, ghost_nodes))
    end

    display("Error")
    display(error_x)
    display(error_z)
    apply_recovery(QS, error_x, error_z)
    measurement_circuit!(QS, d, connections, x_ancilla_list, z_ancilla_list) 
    for i in x_ancilla_list
        final_measurement_values[2,i] = measure!(QS, i)
    end

    for i in z_ancilla_list
        final_measurement_values[2,i] = measure!(QS, i)
    end
    
    display(measurement_values)
    for i = 1:total_qubits
        final_measurement_values[1,i] = measurement_values[1,i]
        last_measurement[1,i] = measurement_values[1,i]
    end

    display(final_measurement_values)
    # Generate faults from the measurement value of initial and final cycle. Tuple containing x and z ancilla
    final_fault_list = generate_fault_nodes(d, final_measurement_values, x_ancilla_list, z_ancilla_list)
    display("Fault")
    display(final_fault_list)

    # Find the most likely faults by using the shortest path and minimum weight matching algorithms
    pushfirst!(PyVector(pyimport("sys")."path"), "")
    fault_search = pyimport("fault_search")
    fault_edges_vertex = fault_search.ideal_recovery("CSC_G_vertex.txt", d, final_fault_list[1], 100)
    fault_edges_plaquette = fault_search.ideal_recovery("CSC_G_plaquette.txt", d, final_fault_list[2], 100)
    display("Matching")
    display(fault_edges_plaquette)
    display(fault_edges_vertex)

    final_error_x::Vector{Int64} = []
    final_error_z::Vector{Int64} = []
    # Use the fault edges to find the qubits where the errors have occurred and apply recovery 
    if isempty(fault_edges_plaquette) == false
        append!(final_error_x, find_x_error_qubits(d, connections, z_ancilla_list, fault_edges_plaquette, ghost_nodes))
    end

    if isempty(fault_edges_vertex) == false
        append!(final_error_z, find_z_error_qubits(d, connections, x_ancilla_list, fault_edges_vertex, ghost_nodes))
    end

    display("Error")
    display(final_error_x)
    display(final_error_z)
    apply_recovery(QS, final_error_x, final_error_z)
    ancilla_reset(QS, final_measurement_values[2,:])
    measurement_circuit!(QS, d, connections, x_ancilla_list, z_ancilla_list) 
    for i in x_ancilla_list
        last_measurement[2,i] = measure!(QS, i)
    end

    for i in z_ancilla_list
        last_measurement[2,i] = measure!(QS, i)
    end
    display(last_measurement)
    final_code_state::Int64 = commutation_check(distill_stabilizers(deepcopy(QS), d), d)
    display(final_code_state)
    return final_code_state
    =#
end

function run()
    # main(3)
    logical_error_list::Vector{Float64} = []
    physical_error_list = range(0.0001, 0.001, length = 11)
    for j in physical_error_list
        count::Int64 = 0
        for i = 1:10000
            if main(3, j) == 1
                count += 1
            end
        end
        append!(logical_error_list, count/10000)
        display(j)
        display(count/10000)
    end
    clf()
    plot(physical_error_list, logical_error_list)
    gcf()
end

function check()
    count::Int64 = 0
    for i = 1:100
        # display("run")
        if main(3, 0.005) == 1
            count += 1
        end
    end
    display(count)
end



