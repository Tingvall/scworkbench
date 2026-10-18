"""Fresh synthetic HDF5-v1 producer, using the accepted Python UTF-8 VLEN layout."""
import sys
import h5py
import numpy as np

with h5py.File(sys.argv[1], "w") as handle:
    # Frozen HDF5-v1 portability boundary: h5py writes the transpose so
    # rhdf5/R's logical rows x dimensions and numeric order are unchanged.
    handle.create_dataset("coordinates", data=np.arange(1, 13, dtype=np.float64).reshape((4, 3), order="F").T, chunks=(3, 4))
    handle.create_dataset("cell_ids", data=["c雪1", "c2", "c3", "c4"], dtype=h5py.string_dtype("utf-8"))
    handle.create_dataset("dim_labels", data=["d1", "dim_雪", "d3"], dtype=h5py.string_dtype("utf-8"))
    handle.attrs.update(schema_version="scworkbench.dense-space.hdf5.v1", space_id="source", n_cells=4, n_dims=3,
                        dtype="float64", endianness="little", chunk_rows=4, chunk_dims=3)
