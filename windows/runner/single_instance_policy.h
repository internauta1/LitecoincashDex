#ifndef RUNNER_SINGLE_INSTANCE_POLICY_H_
#define RUNNER_SINGLE_INSTANCE_POLICY_H_

struct SingleInstancePolicy {
  const wchar_t* mutex_name;
  const wchar_t* window_title;
  bool activate_existing_window;
};

constexpr SingleInstancePolicy GetSingleInstancePolicy(bool isolated) {
  return isolated
      ? SingleInstancePolicy{
            L"Local\\LitecoinCashDEXNext_Isolated_RPC17993_SingleInstanceMutex",
            L"LitecoinCashDEX Next [isolated:17993]", false}
      : SingleInstancePolicy{
            L"Global\\LitecoinCashDEXNext_SingleInstanceMutex",
            L"LitecoinCashDEX Next", true};
}

#endif  // RUNNER_SINGLE_INSTANCE_POLICY_H_
