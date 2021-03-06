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

function prep_x_ancillas!(QS::QuantumState, x_ancilla_list::Vector{Int64})
    for i in x_ancilla_list
        apply_h!(QS,i)
    end
end

function north_z_ancillas!(QS::QuantumState, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j-1 in graph[j]
            apply_cnot!(QS, j-1, j)
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

function west_z_ancillas!(QS::QuantumState, d::Int64, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j-(2*d-1) in graph[j]
            apply_cnot!(QS, j-(2*d-1), j)
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

function east_z_ancillas!(QS::QuantumState, d::Int64, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j+(2*d-1) in graph[j]
            apply_cnot!(QS, j+(2*d-1), j)
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

function south_z_ancillas!(QS::QuantumState, graph::Dict, z_ancilla_list::Vector{Int64})
    for j in z_ancilla_list
        if j+1 in graph[j]
            apply_cnot!(QS, j+1, j)
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
        add_edge!(G_z, i, d*(d-1) + i)
        add_edge!(G_z, i + d*(d+1), d*(d-1) + i + d*(d+1))
        add_edge!(G_x, 1 + (i-1)*(d-1), d*(d-1) + 2*(i-1) + 1)
        add_edge!(G_x, 1 + (i-1)*(d-1) + d*(d+1), d*(d-1) + 2*(i-1) + 1 + d*(d+1))
        add_edge!(G_z, i + d*(d-2), i + d*(d-2) + 2*d)
        add_edge!(G_z, i + d*(d-2) + d*(d+1), i + d*(d-2) + 2*d + d*(d+1))
        add_edge!(G_x, (d-1)*i, d*(d-1) + 2*i)
        add_edge!(G_x, (d-1)*i + d*(d+1), d*(d-1) + 2*i + d*(d+1))
    end

    CSC_G_x = findnz(adjacency_matrix(G_x))
    CSC_G_z = findnz(adjacency_matrix(G_z))
    open("G_vertex"*string(d)*".txt", "w") do f
        for i = 1:length(CSC_G_x[1])
            println(f, (CSC_G_x[1][i], CSC_G_x[2][i]))
        end
    end

    open("G_plaquette"*string(d)*".txt", "w") do f
        for i = 1:length(CSC_G_z[1])
            println(f, (CSC_G_z[1][i], CSC_G_z[2][i]))
        end
    end
end

function main(d::Int64)
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

    # Only run the below function once to generate the initial error lattice
    generate_fault_graph(QS, d, connections, x_ancilla_list, z_ancilla_list, 
    zeros(Int64, (d, total_qubits)))
end