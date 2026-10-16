trigger CasePulseReopen on Case(before update) {
  CasePulseReopenHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
}
