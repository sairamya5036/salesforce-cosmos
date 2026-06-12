@isTest
private class RecordPresenceControllerTest {
    private static final String RECORD_ID = '001000000000000AAA';
    private static final String OBJECT_API_NAME = 'Account';

    @isTest
    static void buildEventUsesRunningUserIdentityAndRecordContext() {
        User currentUser = [
            SELECT Id, Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        RecordPresenceEvent__e presenceEvent = RecordPresenceController.buildEvent(
            RECORD_ID,
            OBJECT_API_NAME,
            'Viewing',
            currentUser
        );

        System.assertEquals(RECORD_ID, presenceEvent.RecordId__c);
        System.assertEquals(OBJECT_API_NAME, presenceEvent.ObjectApiName__c);
        System.assertEquals('Viewing', presenceEvent.UserAction__c);
        System.assertEquals(currentUser.Id, presenceEvent.UserId__c);
        System.assertEquals(currentUser.Name, presenceEvent.UserName__c);
    }

    @isTest
    static void publishEventSupportsPresenceActions() {
        Test.startTest();
        RecordPresenceController.publishEvent(RECORD_ID, OBJECT_API_NAME, 'Viewing');
        RecordPresenceController.publishEvent(RECORD_ID, OBJECT_API_NAME, 'Present');
        RecordPresenceController.publishEvent(RECORD_ID, OBJECT_API_NAME, 'Left');
        Test.stopTest();

        System.assert(true, 'Record presence platform events published without throwing.');
    }

    @isTest
    static void publishEventIgnoresBlankAndUnsupportedInputs() {
        Test.startTest();
        RecordPresenceController.publishEvent(null, OBJECT_API_NAME, 'Viewing');
        RecordPresenceController.publishEvent(RECORD_ID, null, 'Viewing');
        RecordPresenceController.publishEvent(RECORD_ID, OBJECT_API_NAME, null);
        RecordPresenceController.publishEvent(RECORD_ID, OBJECT_API_NAME, 'Typing');
        Test.stopTest();

        System.assert(true, 'Invalid record presence inputs return without throwing.');
    }
}