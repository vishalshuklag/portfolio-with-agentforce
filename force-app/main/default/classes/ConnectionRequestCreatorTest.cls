@isTest
private class ConnectionRequestCreatorTest {

    @isTest
    static void createsLeadForValidRequest() {
        ConnectionRequestCreator.Request req = new ConnectionRequestCreator.Request();
        req.visitorName = 'Ada Lovelace';
        req.visitorEmail = 'ada@example.com';
        req.visitorMessage = 'I would like to collaborate.';

        Test.startTest();
        List<ConnectionRequestCreator.Result> results =
            ConnectionRequestCreator.createRequests(
                new List<ConnectionRequestCreator.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assert(results[0].confirmationMessage.contains('ada@example.com'));

        List<Lead> leads = [SELECT FirstName, LastName, Email, Company, Description FROM Lead];
        System.assertEquals(1, leads.size());
        System.assertEquals('Ada', leads[0].FirstName);
        System.assertEquals('Lovelace', leads[0].LastName);
        System.assert(leads[0].Description.contains('collaborate'));
    }

    @isTest
    static void rejectsInvalidEmailAndMissingFields() {
        ConnectionRequestCreator.Request badEmail = new ConnectionRequestCreator.Request();
        badEmail.visitorName = 'No Email';
        badEmail.visitorEmail = 'not-an-email';
        badEmail.visitorMessage = 'Hi';

        ConnectionRequestCreator.Request missing = new ConnectionRequestCreator.Request();
        missing.visitorName = 'Only Name';

        Test.startTest();
        List<ConnectionRequestCreator.Result> results =
            ConnectionRequestCreator.createRequests(
                new List<ConnectionRequestCreator.Request>{ badEmail, missing }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Invalid email rejected');
        System.assertEquals(false, results[1].success, 'Missing fields rejected');
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'No leads created');
    }
}