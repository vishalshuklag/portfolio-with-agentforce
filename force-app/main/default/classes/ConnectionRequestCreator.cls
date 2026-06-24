/**
 * Backing logic for the Personal Portfolio Agent template.
 * Saves a visitor connection request as a Lead so the site owner can follow up.
 */
public with sharing class ConnectionRequestCreator {

    public class Request {
        @InvocableVariable(
            label='Visitor Name'
            description='Full name of the visitor'
            required=true
        )
        public String visitorName;
        @InvocableVariable(
            label='Visitor Email'
            description='Email address of the visitor'
            required=true
        )
        public String visitorEmail;
        @InvocableVariable(
            label='Visitor Message'
            description='Why the visitor wants to connect'
            required=true
        )
        public String visitorMessage;
    }

    public class Result {
        @InvocableVariable(
            label='Confirmation Message'
            description='Friendly confirmation to relay to the visitor'
        )
        public String confirmationMessage;
        @InvocableVariable(
            label='Success'
            description='True when the connection request was saved'
        )
        public Boolean success;
    }

    @InvocableMethod(
        label='Create Connection Request'
        description='Saves the visitor name, email, and message as a Lead for the site owner'
    )
    public static List<Result> createRequests(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<Lead> leadsToInsert = new List<Lead>();
        List<Integer> leadResultIndex = new List<Integer>();

        for (Request req : requests) {
            Result res = new Result();
            res.success = false;

            String visitorName = (req == null) ? null : req.visitorName?.trim();
            String visitorEmail = (req == null) ? null : req.visitorEmail?.trim();
            String visitorMessage = (req == null) ? null : req.visitorMessage?.trim();

            if (String.isBlank(visitorName) || String.isBlank(visitorEmail) || String.isBlank(visitorMessage)) {
                res.confirmationMessage = 'I still need your name, email, and a short message to pass along.';
                results.add(res);
                continue;
            }
            if (!Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', visitorEmail)) {
                res.confirmationMessage = 'That email address does not look valid. Could you double-check it?';
                results.add(res);
                continue;
            }

            String firstName = null;
            String lastName = visitorName;
            Integer spaceIdx = visitorName.indexOf(' ');
            if (spaceIdx > 0) {
                firstName = visitorName.substring(0, spaceIdx);
                lastName = visitorName.substring(spaceIdx + 1).trim();
            }

            Lead newLead = new Lead(
                FirstName = firstName,
                LastName = lastName,
                Email = visitorEmail,
                Company = 'Portfolio Inquiry',
                LeadSource = 'Web',
                Description = 'Connection request via Portfolio Agent: ' + visitorMessage
            );
            leadsToInsert.add(newLead);
            leadResultIndex.add(results.size());
            results.add(res);
        }

        if (!leadsToInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(leadsToInsert, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Result res = results[leadResultIndex[i]];
                if (saveResults[i].isSuccess()) {
                    res.success = true;
                    res.confirmationMessage = 'Thanks! Your message has been passed along, and you can expect a reply at ' + leadsToInsert[i].Email + ' soon.';
                } else {
                    res.confirmationMessage = 'Sorry, I could not save your request right now. Please try again in a moment.';
                }
            }
        }
        return results;
    }
}