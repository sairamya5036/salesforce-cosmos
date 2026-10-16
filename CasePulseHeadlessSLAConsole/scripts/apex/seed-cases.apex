// Synthetic scenarios. No real customer records. Safe to repeat without duplicates.
System.assertEquals(0,[SELECT COUNT() FROM Case WHERE CasePulse_Demo__c=true], 'Demo cases already exist. Do not duplicate them.');
Id queueId=[SELECT Id FROM Group WHERE DeveloperName='CasePulse_Support' AND Type='Queue'].Id;
Datetime nowAt=System.now();
List<Case> records = new List<Case>{
 new Case(Subject='[DEMO] Northstar — checkout outage',Priority='High',OwnerId=queueId,CasePulse_Demo_Deadline__c=nowAt.addMinutes(-20),CasePulse_Reopen_Count__c=2),
 new Case(Subject='[DEMO] Meridian — payment retries failing',Priority='High',OwnerId=queueId,CasePulse_Demo_Deadline__c=nowAt.addMinutes(25)),
 new Case(Subject='[DEMO] Acme — account access blocked',Priority='High',OwnerId=UserInfo.getUserId(),CasePulse_Demo_Deadline__c=nowAt.addMinutes(45)),
 new Case(Subject='[DEMO] Summit — reopened integration issue',Priority='Medium',OwnerId=UserInfo.getUserId(),CasePulse_Reopen_Count__c=3),
 new Case(Subject='[DEMO] Harbor — awaiting a response',Priority='Medium',OwnerId=UserInfo.getUserId()),
 new Case(Subject='[DEMO] Orbit — setup question',Priority='Low',OwnerId=UserInfo.getUserId(),CasePulse_Demo_Deadline__c=nowAt.addHours(24))
};
for(Case c:records) { c.Status='New';c.Origin='Web';c.CasePulse_Demo__c=true;c.Description='Fictional CasePulse portfolio case. Demo SLA and seeded reopen history are synthetic.'; }
insert records;
// Salesforce does not allow changing CreatedDate outside tests. An old outgoing
// EmailMessage provides a genuine, visibly synthetic stale-response signal.
insert new EmailMessage(ParentId=records[4].Id,Incoming=false,Status='3',Subject='[DEMO] Prior support reply',FromAddress='support@example.invalid',ToAddress='customer@example.invalid',TextBody='Synthetic demo response.',MessageDate=nowAt.addHours(-10));
System.debug('Created six fictional CasePulse cases. Refresh analysis before deadline screenshots.');
