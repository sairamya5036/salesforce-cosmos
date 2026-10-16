@IsTest
private class CasePulseTests {
  @TestSetup
  static void setup() {
    User rep = user('cprep');
    User manager = user('cpmgr');
    User outsider = user('cpout');
    User denied = user('cpdeny');
    denied.ProfileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ]
    .Id;
    User reader = user('cpread');
    reader.ProfileId = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1]
    .Id;
    insert new List<User>{ rep, manager, outsider, denied, reader };
    Id userPerm = [SELECT Id FROM PermissionSet WHERE Name = 'CasePulse_User']
    .Id;
    Id managerPerm = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'CasePulse_Manager'
    ]
    .Id;
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = rep.Id,
        PermissionSetId = userPerm
      ),
      new PermissionSetAssignment(
        AssigneeId = manager.Id,
        PermissionSetId = userPerm
      ),
      new PermissionSetAssignment(
        AssigneeId = manager.Id,
        PermissionSetId = managerPerm
      ),
      new PermissionSetAssignment(
        AssigneeId = outsider.Id,
        PermissionSetId = userPerm
      ),
      new PermissionSetAssignment(
        AssigneeId = reader.Id,
        PermissionSetId = userPerm
      )
    };
    Id queue = [
      SELECT Id
      FROM Group
      WHERE DeveloperName = 'CasePulse_Support' AND Type = 'Queue'
    ]
    .Id;
    insert new GroupMember(GroupId = queue, UserOrGroupId = rep.Id);
    System.runAs(rep) {
      insert new List<Case>{
        new Case(
          Subject = 'Own breached case',
          Status = 'New',
          Origin = 'Web',
          Priority = 'High',
          OwnerId = rep.Id,
          CasePulse_Demo_Deadline__c = System.now().addMinutes(-10),
          CasePulse_Demo__c = true
        ),
        new Case(
          Subject = 'Queue case',
          Status = 'New',
          Origin = 'Web',
          Priority = 'High',
          OwnerId = queue,
          CasePulse_Demo_Deadline__c = System.now().addMinutes(30),
          CasePulse_Demo__c = true
        ),
        new Case(
          Subject = 'Outside team',
          Status = 'New',
          Origin = 'Web',
          OwnerId = outsider.Id,
          CasePulse_Demo__c = true
        ),
        new Case(
          Subject = 'Read only case',
          Status = 'New',
          Origin = 'Web',
          OwnerId = reader.Id,
          CasePulse_Demo__c = true
        )
      };
    }
  }
  private static User user(String alias) {
    return new User(
      Alias = alias,
      LastName = alias,
      Email = alias + '@example.invalid',
      Username = alias + System.now().getTime() + '@example.invalid',
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'America/New_York',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }
  private static User actor(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }
  private static Case ownCase() {
    return [SELECT Id FROM Case WHERE Subject = 'Own breached case' LIMIT 1];
  }
  @IsTest
  static void scoringBoundaries() {
    Datetime nowAt = Datetime.newInstanceGmt(2026, 10, 16, 16, 0, 0);
    Id queue = [
      SELECT Id
      FROM Group
      WHERE DeveloperName = 'CasePulse_Support' AND Type = 'Queue'
    ]
    .Id;
    Case record = (Case) JSON.deserialize(
      '{"Id":"500000000000001","CaseNumber":"00001","CreatedDate":"2026-10-16T16:00:00.000Z","Subject":"Synthetic","Priority":"Medium","IsEscalated":false,"CasePulse_Reopen_Count__c":0}',
      Case.class
    );
    record.OwnerId = UserInfo.getUserId();
    System.assertEquals(
      0,
      CaseRiskAnalyzer.score(record, null, 'SLA unavailable', null, nowAt).score
    );
    System.assertEquals(
      60,
      CaseRiskAnalyzer.score(record, nowAt, 'Demo SLA', null, nowAt).score
    );
    System.assertEquals(
      40,
      CaseRiskAnalyzer.score(
          record,
          nowAt.addMinutes(60),
          'Demo SLA',
          null,
          nowAt
        )
        .score
    );
    System.assertEquals(
      0,
      CaseRiskAnalyzer.score(
          record,
          nowAt.addSeconds(3601),
          'Demo SLA',
          null,
          nowAt
        )
        .score
    );
    Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(
      JSON.serialize(record)
    );
    values.put('CreatedDate', nowAt.addHours(-8));
    record = (Case) JSON.deserialize(JSON.serialize(values), Case.class);
    System.assertEquals(
      20,
      CaseRiskAnalyzer.score(record, null, 'SLA unavailable', null, nowAt).score
    );
    System.assertEquals(
      0,
      CaseRiskAnalyzer.score(
          record,
          null,
          'SLA unavailable',
          nowAt.addSeconds(-28799),
          nowAt
        )
        .score
    );
    record.CasePulse_Reopen_Count__c = 2;
    System.assertEquals(
      'High',
      CaseRiskAnalyzer.score(record, null, 'SLA unavailable', null, nowAt)
        .severity
    );
    record.OwnerId = queue;
    record.Priority = 'High';
    System.assertEquals(
      100,
      CaseRiskAnalyzer.score(record, nowAt, 'CaseMilestone', null, nowAt).score
    );
  }
  @IsTest
  static void repScopeAndDenial() {
    System.runAs(actor('cprep')) {
      CaseRiskAnalyzer.Request req = new CaseRiskAnalyzer.Request();
      req.view = 'MY';
      CaseRiskAnalyzer.ConsoleData data = CaseRiskAnalyzer.analyze(
          new List<CaseRiskAnalyzer.Request>{ req }
        )[0]
        .console;
      System.assertEquals(1, data.totalCount);
      System.assertEquals('My SLA Rescue Queue', data.title);
      req.view = 'TEAM';
      try {
        CaseRiskAnalyzer.analyze(new List<CaseRiskAnalyzer.Request>{ req });
        System.assert(false, 'Team query must fail');
      } catch (CasePulseAccess.AccessException e) {
        System.assert(e.getMessage().contains('permission'));
      }
      req.view = 'ALL';
      try {
        CaseRiskAnalyzer.analyze(new List<CaseRiskAnalyzer.Request>{ req });
        System.assert(false, 'Invalid view must fail');
      } catch (CasePulseAccess.AccessException e) {
        System.assert(e.getMessage().contains('MY or TEAM'));
      }
      CaseRescuePrepare.Request prep = new CaseRescuePrepare.Request();
      prep.caseId = [SELECT Id FROM Case WHERE Subject = 'Outside team'].Id;
      try {
        CaseRescuePrepare.prepare(new List<CaseRescuePrepare.Request>{ prep });
        System.assert(false, 'Out-of-scope rescue must fail');
      } catch (CasePulseAccess.AccessException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }
  @IsTest
  static void managerScopeAndRanking() {
    System.runAs(actor('cpmgr')) {
      CaseRiskAnalyzer.Request req = new CaseRiskAnalyzer.Request();
      CaseRiskAnalyzer.ConsoleData data = CaseRiskAnalyzer.analyze(
          new List<CaseRiskAnalyzer.Request>{ req }
        )[0]
        .console;
      System.assertEquals('TEAM', data.view);
      System.assertEquals(2, data.totalCount);
      System.assertEquals('Queue case', data.cases[0].subject); // 40+25 beats 60.
      System.assertEquals(2, data.criticalCount);
    }
  }
  @IsTest
  static void approvedRescueIsAtomicAndIdempotent() {
    System.runAs(actor('cprep')) {
      Id caseId = ownCase().Id;
      CaseRescuePrepare.Request prep = new CaseRescuePrepare.Request();
      prep.caseId = caseId;
      System.assert(
        CaseRescuePrepare.prepare(
            new List<CaseRescuePrepare.Request>{ prep }
          )[0]
          .confirmationUrl.contains('/flow/CasePulse_Confirm_Rescue?caseId=')
      );
      System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :caseId]);
      CaseRescueApply.Request req = new CaseRescueApply.Request();
      req.caseId = caseId;
      req.approved = false;
      try {
        CaseRescueApply.apply(new List<CaseRescueApply.Request>{ req });
        System.assert(false, 'Approval required');
      } catch (CasePulseAccess.AccessException e) {
        System.assert(e.getMessage().contains('approval'));
      }
      System.assertEquals(
        false,
        [SELECT IsEscalated FROM Case WHERE Id = :caseId].IsEscalated
      );
      req.approved = true;
      Test.startTest();
      CaseRescueApply.apply(new List<CaseRescueApply.Request>{ req, req });
      CaseRescueApply.apply(new List<CaseRescueApply.Request>{ req });
      Test.stopTest();
      System.assertEquals(
        true,
        [SELECT IsEscalated FROM Case WHERE Id = :caseId].IsEscalated
      );
      System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :caseId]);
    }
  }
  @IsTest
  static void closeThenReopen() {
    System.runAs(actor('cprep')) {
      Case record = ownCase();
      String closedStatus = [
        SELECT MasterLabel
        FROM CaseStatus
        WHERE IsClosed = TRUE
        LIMIT 1
      ]
      .MasterLabel;
      record.Status = closedStatus;
      update record;
      CaseRescueApply.Request req = new CaseRescueApply.Request();
      req.caseId = record.Id;
      req.approved = true;
      try {
        CaseRescueApply.apply(new List<CaseRescueApply.Request>{ req });
        System.assert(false, 'Closed case must fail');
      } catch (CasePulseAccess.AccessException e) {
        System.assertNotEquals(null, e.getMessage());
      }
      record.Status = 'New';
      update record;
      System.assertEquals(
        1,
        [SELECT CasePulse_Reopen_Count__c FROM Case WHERE Id = :record.Id]
        .CasePulse_Reopen_Count__c
      );
      record.CasePulse_Reopen_Count__c = 99;
      update record;
      System.assertEquals(
        1,
        [SELECT CasePulse_Reopen_Count__c FROM Case WHERE Id = :record.Id]
        .CasePulse_Reopen_Count__c
      );
    }
  }
  @IsTest
  static void truncatedAndEmptyResults() {
    System.runAs(actor('cpout')) {
      CaseRiskAnalyzer.Request req = new CaseRiskAnalyzer.Request();
      req.view = 'MY';
      Case record = [SELECT Id FROM Case WHERE Subject = 'Outside team'];
      record.Status = [
        SELECT MasterLabel
        FROM CaseStatus
        WHERE IsClosed = TRUE
        LIMIT 1
      ]
      .MasterLabel;
      update record;
      System.assertEquals(
        true,
        CaseRiskAnalyzer.analyze(new List<CaseRiskAnalyzer.Request>{ req })[0]
          .console.empty
      );
      List<Case> records = new List<Case>();
      for (Integer i = 0; i < 22; i++)
        records.add(
          new Case(
            Subject = 'Bulk ' + i,
            Status = 'New',
            Origin = 'Web',
            OwnerId = UserInfo.getUserId()
          )
        );
      insert records;
      CaseRiskAnalyzer.ConsoleData data = CaseRiskAnalyzer.analyze(
          new List<CaseRiskAnalyzer.Request>{ req }
        )[0]
        .console;
      System.assertEquals(22, data.totalCount);
      System.assertEquals(20, data.cases.size());
      System.assertEquals(true, data.truncated);
    }
  }
  @IsTest
  static void deniedReadAndAtomicWriteFailure() {
    System.runAs(actor('cpdeny')) {
      try {
        CaseRiskAnalyzer.analyze(
          new List<CaseRiskAnalyzer.Request>{ new CaseRiskAnalyzer.Request() }
        );
        System.assert(false, 'Missing Case/FLS access must fail');
      } catch (SecurityException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
    Id target = [SELECT Id FROM Case WHERE Subject = 'Read only case'].Id;
    System.runAs(actor('cpread')) {
      CaseRescueApply.Request req = new CaseRescueApply.Request();
      req.caseId = target;
      req.approved = true;
      try {
        CaseRescueApply.apply(new List<CaseRescueApply.Request>{ req });
        System.assert(false, 'Read-only user cannot rescue');
      } catch (TypeException e) {
        System.assert(e.getMessage().contains('Task'));
      }
    }
    System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :target]);
    Case unchanged = [
      SELECT IsEscalated, CasePulse_Rescue_Task__c
      FROM Case
      WHERE Id = :target
    ];
    System.assertEquals(false, unchanged.IsEscalated);
    System.assertEquals(null, unchanged.CasePulse_Rescue_Task__c);
  }
  @IsTest
  static void flowPreparationDoesNotWrite() {
    System.runAs(actor('cprep')) {
      Id target = ownCase().Id;
      Flow.Interview.CasePulse_Prepare_Rescue interview = new Flow.Interview.CasePulse_Prepare_Rescue(
        new Map<String, Object>{ 'caseId' => String.valueOf(target) }
      );
      interview.start();
      System.assert(
        String.valueOf(interview.getVariableValue('confirmationUrl'))
          .contains(String.valueOf(target))
      );
      System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :target]);
      System.assertEquals(
        false,
        [SELECT IsEscalated FROM Case WHERE Id = :target].IsEscalated
      );
      insert new EmailMessage(
        ParentId = target,
        Incoming = false,
        Status = '3',
        Subject = 'Synthetic old reply',
        FromAddress = 'support@example.invalid',
        ToAddress = 'customer@example.invalid',
        MessageDate = System.now().addHours(-10)
      );
      CaseRiskAnalyzer.Request req = new CaseRiskAnalyzer.Request();
      req.view = 'MY';
      CaseRiskAnalyzer.ConsoleData data = CaseRiskAnalyzer.analyze(
          new List<CaseRiskAnalyzer.Request>{ req }
        )[0]
        .console;
      System.assertEquals(80, data.cases[0].score);
      System.assert(data.cases[0].lastResponseAt.contains('outbound email'));
    }
  }
  @IsTest
  static void demoFilterKeepsScope() {
    System.runAs(actor('cprep')) {
      insert new Case(
        Subject = 'Non-demo case',
        Status = 'New',
        Origin = 'Web',
        OwnerId = UserInfo.getUserId()
      );
      CaseRiskAnalyzer.Request req = new CaseRiskAnalyzer.Request();
      req.view = 'MY';
      req.demoOnly = true;
      CaseRiskAnalyzer.ConsoleData data = CaseRiskAnalyzer.analyze(
          new List<CaseRiskAnalyzer.Request>{ req }
        )[0]
        .console;
      System.assertEquals(1, data.totalCount);
      System.assert(data.notice.startsWith('Fictional demo cases only.'));
      System.assert(data.refreshPrompt.contains('demoOnly true'));
    }
  }
  @IsTest
  static void bulkManagerRescueAndChangedOwnership() {
    System.runAs(actor('cpmgr')) {
      Id queueId = [
        SELECT Id
        FROM Group
        WHERE DeveloperName = 'CasePulse_Support' AND Type = 'Queue'
      ]
      .Id;
      List<Case> records = new List<Case>();
      for (Integer i = 0; i < 200; i++)
        records.add(
          new Case(
            Subject = 'Bulk rescue ' + i,
            Status = 'New',
            Origin = 'Web',
            OwnerId = queueId
          )
        );
      insert records;
      List<CaseRescuePrepare.Request> preparations = new List<CaseRescuePrepare.Request>();
      List<CaseRescueApply.Request> approvals = new List<CaseRescueApply.Request>();
      Set<Id> ids = new Set<Id>();
      for (Case record : records) {
        ids.add(record.Id);
        CaseRescuePrepare.Request prep = new CaseRescuePrepare.Request();
        prep.caseId = record.Id;
        preparations.add(prep);
        CaseRescueApply.Request approval = new CaseRescueApply.Request();
        approval.caseId = record.Id;
        approval.approved = true;
        approvals.add(approval);
      }
      Test.startTest();
      System.assertEquals(200, CaseRescuePrepare.prepare(preparations).size());
      System.assertEquals(200, CaseRescueApply.apply(approvals).size());
      Test.stopTest();
      System.assertEquals(200, [SELECT COUNT() FROM Task WHERE WhatId IN :ids]);
      Case record = [SELECT Id, OwnerId FROM Case WHERE Subject = 'Queue case'];
      CaseRescuePrepare.Request prep = new CaseRescuePrepare.Request();
      prep.caseId = record.Id;
      CaseRescuePrepare.prepare(new List<CaseRescuePrepare.Request>{ prep });
      record.OwnerId = actor('cpout').Id;
      update record;
      CaseRescueApply.Request approval = new CaseRescueApply.Request();
      approval.caseId = record.Id;
      approval.approved = true;
      try {
        CaseRescueApply.apply(new List<CaseRescueApply.Request>{ approval });
        System.assert(false, 'Recheck ownership at approval');
      } catch (CasePulseAccess.AccessException e) {
        System.assertNotEquals(null, e.getMessage());
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Task WHERE WhatId = :record.Id]
      );
    }
  }
}
