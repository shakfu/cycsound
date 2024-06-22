s = '''
debug_mode
buffer_frames
hardware_buffer_frames
displays
ascii_graphs
postscript_graphs
message_level
tempo
ring_bell
defer_gen01_load
midi_key
midi_key_cps
midi_key_oct
midi_key_pch
midi_velocity
midi_velocity_amp
no_default_paths
number_of_threads
syntax_check_only
csd_line_counts
compute_weights
realtime_mode
sample_accurate
sample_rate_override
control_rate_override
nchnls_override
nchnls_i_override
e0dbfs_override
daemon
ksmps_override
'''

for i in s.splitlines():
	print('@property')
	print(f'def {i}(self) -> int:')
	print(f'    return self.ptr.{i}')
	print()
	print(f'@{i}.setter')
	print(f'def {i}(self, int value):')
	print(f'    self.ptr.{i} = value')
	print()
