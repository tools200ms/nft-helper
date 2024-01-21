#!/bin/bash

nft flush ruleset

# add filter chain to ip table 'test.tbl'
nft add table ip test_tbl

# add OUTPUT hook
nft add chain test_tbl test_out { type filter hook output priority 0 \; }

nft add set ip test_tbl testset1d { type ipv4_addr \; flags timeout,interval \; }
nft add set ip test_tbl testset2s { type ipv4_addr \; flags interval \; }

# add counter
nft add rule ip test_tbl test_out ip daddr @testset1d counter
nft add rule ip test_tbl test_out ip saddr @testset2s counter

nft list ruleset

exit 0