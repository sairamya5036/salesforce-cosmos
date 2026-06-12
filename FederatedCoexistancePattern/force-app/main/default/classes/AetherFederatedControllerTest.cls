@IsTest
private class AetherFederatedControllerTest {
    private class MultiServiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(200);

            if (request.getEndpoint().contains('/erp/customer/')) {
                response.setBody('{"production_status":"Assembling","chip_type":"High-Efficiency Blue","current_production_batch":"BATCH-2048","quality_control_status":"Passed","shipping_eta":"2026-04-15","warehouse_location":"Atlanta DC"}');
                return response;
            }

            if (request.getEndpoint().contains('/finance/customer/')) {
                response.setBody('{"credit_limit":50000,"balance_due":1250,"dso":18,"payment_history":"On-time"}');
                return response;
            }

            response.setStatusCode(404);
            response.setBody('{"error":"not_found"}');
            return response;
        }
    }

    @IsTest
    static void returnsFederatedData() {
        Account account = new Account(
            Name = 'Aether LED',
            Global_UUID__c = 'AETHER-LED-99',
            Account_Tier__c = 'Gold',
            Phone = '555-0100',
            Website = 'https://aether.example.com'
        );
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Q2 Expansion',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 2000000
        );
        insert opp;

        Case supportCase = new Case(
            AccountId = account.Id,
            Subject = 'Shipment follow-up',
            Status = 'New',
            Origin = 'Phone'
        );
        insert supportCase;

        Test.setMock(HttpCalloutMock.class, new MultiServiceMock());

        Test.startTest();
        AetherFederatedController.FederatedResponse response =
            AetherFederatedController.getFederatedData(account.Id);
        Test.stopTest();

        System.assertEquals('Aether LED', response.accountName);
        System.assertEquals('AETHER-LED-99', response.globalUuid);
        System.assertEquals('Gold', response.crm.tier);
        System.assertEquals(2000000, response.crm.openPipeline);
        System.assertEquals(1, response.crm.openCases);
        System.assertEquals('Assembling', response.erp.productionStatus);
        System.assertEquals('High-Efficiency Blue', response.erp.chipType);
        System.assertEquals(50000, response.billing.creditLimit);
        System.assertEquals(1250, response.billing.balanceDue);
        System.assertEquals(18, response.billing.dso);
        System.assertEquals('Strong', response.healthScore);
        System.assertEquals(0, response.warnings.size());
    }

    @IsTest
    static void throwsWhenUuidMissing() {
        Account account = new Account(Name = 'Missing UUID');
        insert account;

        try {
            AetherFederatedController.getFederatedData(account.Id);
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('Global UUID is missing'));
        }
    }
}
