# Verilog-caches
Various caches written in Verilog-HDL.


4way_4word cache
+ 4-way set associative cache memory
+ Line size is 4word
+ Cache replacement policy is LRU


8way_4word cache
+ 8-way set associative cache memory
+ Line size is 4word
+ Cache replacement policy is Pseudo-LRU


free_config_cache
+ Default cache configuration is 8-way set associative
+ You can change the cache configuration by sending a signal of cache_config
+ When you implement this cache on FPGA, you can change the configuration while FPGA is running


