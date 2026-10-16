// Run only in a development org after core deployment. Fictional data, insert-once.
List<Group> queues = [SELECT Id FROM Group WHERE DeveloperName='CasePulse_Support' AND Type='Queue'];
System.assert(!queues.isEmpty(), 'Deploy CasePulse_Support first.');
Id queueId=queues[0].Id;
Id actorId=UserInfo.getUserId();
if ([SELECT COUNT() FROM GroupMember WHERE GroupId=:queueId AND UserOrGroupId=:actorId]==0) {
    insert new GroupMember(GroupId=queueId,UserOrGroupId=actorId);
}
// Separate setup DML from Case inserts: run seed-cases.apex next.
System.debug('CasePulse support queue membership ready. Now run seed-cases.apex.');
