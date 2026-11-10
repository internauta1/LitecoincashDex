// Existing deterministic suites, collected without the integration harness.
import '../balance_utils/compute_wallet_total_usd_tests.dart';
import '../nfts/nft_supported_chains_test.dart';
import '../swaps/my_recent_swaps_response_tests.dart';

void main() {
  testComputeWalletTotalUsd();
  testNftSupportedChains();
  testMyRecentSwapsResponse();
}
