public with sharing class CasePulseAccess {
  public class AccessException extends Exception {
  }
  public static Boolean isManager() {
    return FeatureManagement.checkPermission('CasePulse_Manager');
  }
  public static Set<Id> ownerScope(Boolean teamView) {
    Set<Id> owners = new Set<Id>{ UserInfo.getUserId() };
    if (!teamView)
      return owners;
    if (!isManager())
      throw new AccessException(
        'Team access requires CasePulse Manager permission.'
      );
    owners.clear();
    List<Group> queues = [
      SELECT Id
      FROM Group
      WHERE Type = 'Queue' AND DeveloperName = 'CasePulse_Support'
    ];
    if (queues.isEmpty())
      return owners;
    Id queueId = queues[0].Id;
    owners.add(queueId);
    // Setup membership is used only for scoping. Case reads still enforce USER_MODE.
    for (GroupMember member : [
      SELECT UserOrGroupId
      FROM GroupMember
      WHERE GroupId = :queueId
    ]) {
      if (member.UserOrGroupId.getSObjectType() == User.SObjectType)
        owners.add(member.UserOrGroupId);
    }
    return owners;
  }
  public static Set<Id> rescueOwners() {
    Set<Id> owners = ownerScope(isManager());
    owners.add(UserInfo.getUserId());
    return owners;
  }
  public static void requireCase(Case record, Set<Id> owners) {
    if (!owners.contains(record.OwnerId) || record.IsClosed) {
      throw new AccessException(
        'This open case is outside your authorized rescue queue.'
      );
    }
  }
}
