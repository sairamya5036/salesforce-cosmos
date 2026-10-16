public class CasePulseReopenHandler {
  public static void beforeUpdate(
    List<Case> records,
    Map<Id, Case> oldRecords
  ) {
    Set<String> closedStatuses = new Set<String>();
    for (CaseStatus status : [
      SELECT MasterLabel
      FROM CaseStatus
      WHERE IsClosed = TRUE
    ])
      closedStatuses.add(status.MasterLabel);
    for (Case record : records) {
      Case oldRecord = oldRecords.get(record.Id);
      // Ignore direct edits of the counter; only closed-to-open transitions change it.
      Decimal count = oldRecord.CasePulse_Reopen_Count__c == null
        ? 0
        : oldRecord.CasePulse_Reopen_Count__c;
      record.CasePulse_Reopen_Count__c =
        count +
        (oldRecord.IsClosed && !closedStatuses.contains(record.Status) ? 1 : 0);
    }
  }
}
