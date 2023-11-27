MyMooring.jl
============


Verification of mooring system of floating offshore wind turbine. 

Present routines are in agreement with the DNV (Det Norske Veritas) standards:

- **DNV-ST-0119** - Floating wind turbine structures
- **DNVGL-OS-E301** - Position mooring


```julia
include("MyMooring.jl");

using .MyMooring 

MyMooring.main(
    open_ui=true,
    execute=true
)
```