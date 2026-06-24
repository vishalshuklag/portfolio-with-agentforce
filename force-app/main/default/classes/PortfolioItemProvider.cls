/**
 * Backing logic for the Personal Portfolio Agent template.
 * Returns active Portfolio_Item__c records, optionally filtered by Type__c
 * (Bio, Resume, LinkedIn, Blog, YouTube, GitHub, Project).
 */
public with sharing class PortfolioItemProvider {

    public class Request {
        @InvocableVariable(
            label='Item Type'
            description='Category to retrieve: Bio, Resume, LinkedIn, Blog, YouTube, GitHub, or Project. Blank returns all active items.'
        )
        public String itemType;
    }

    public class PortfolioItem {
        @InvocableVariable(
            label='Title'
            description='Title of the portfolio item'
        )
        public String title;
        @InvocableVariable(
            label='Subtitle'
            description='Short subtitle: role, company, issuer, or tagline'
        )
        public String subtitle;
        @InvocableVariable(
            label='Item Type'
            description='Category of the portfolio item'
        )
        public String itemType;
        @InvocableVariable(
            label='URL'
            description='Link to the resource, if any'
        )
        public String url;
        @InvocableVariable(
            label='Secondary URL'
            description='Optional second link (e.g. source repo for a project)'
        )
        public String secondaryUrl;
        @InvocableVariable(
            label='Timeframe'
            description='Human-readable date range, e.g. "Jan 2022 - Present"'
        )
        public String timeframe;
        @InvocableVariable(
            label='Details'
            description='Description text for the portfolio item'
        )
        public String details;
    }

    public class Result {
        @InvocableVariable(
            label='Items'
            description='Matching portfolio items'
        )
        public List<PortfolioItem> items;
        @InvocableVariable(
            label='Has Data'
            description='True when at least one item was found'
        )
        public Boolean hasData;
    }

    @InvocableMethod(
        label='Get Portfolio Items'
        description='Retrieves the active portfolio items of the site owner, optionally filtered by category'
    )
    public static List<Result> getItems(List<Request> requests) {
        List<Portfolio_Item__c> allItems = [
            SELECT Name, Subtitle__c, Type__c, URL__c, Secondary_URL__c,
                   Description__c, Start_Date__c, End_Date__c
            FROM Portfolio_Item__c
            WHERE Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC
            LIMIT 200
        ];

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            String typeFilter = (req != null && String.isNotBlank(req.itemType))
                ? req.itemType.trim()
                : null;

            Result res = new Result();
            res.items = new List<PortfolioItem>();
            for (Portfolio_Item__c record : allItems) {
                if (typeFilter != null && !typeMatches(record.Type__c, typeFilter)) {
                    continue;
                }
                PortfolioItem item = new PortfolioItem();
                item.title = record.Name;
                item.subtitle = record.Subtitle__c;
                item.itemType = record.Type__c;
                item.url = record.URL__c;
                item.secondaryUrl = record.Secondary_URL__c;
                item.timeframe = formatTimeframe(record.Start_Date__c, record.End_Date__c);
                item.details = record.Description__c;
                res.items.add(item);
            }
            res.hasData = !res.items.isEmpty();
            results.add(res);
        }
        return results;
    }

    /**
     * Tolerant category match so the agent still finds data when it passes a
     * close-but-not-exact type (e.g. "Certifications" vs "Certification",
     * "projects" vs "Project", "cert" vs "Certification"). Matches on a
     * case-insensitive equality or a substring relationship, guarded by a
     * minimum length so short tokens cannot match unrelated categories.
     * Returns only real stored categories, so answers stay grounded in data.
     */
    @TestVisible
    private static Boolean typeMatches(String storedType, String filter) {
        if (String.isBlank(storedType) || String.isBlank(filter)) {
            return false;
        }
        String stored = storedType.trim().toLowerCase();
        String wanted = filter.trim().toLowerCase();
        if (stored == wanted) {
            return true;
        }
        return wanted.length() >= 3
            && (stored.contains(wanted) || wanted.contains(stored));
    }

    private static final List<String> MONTHS = new List<String>{
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    };

    private static String formatTimeframe(Date startDate, Date endDate) {
        if (startDate == null && endDate == null) {
            return null;
        }
        String start = (startDate == null) ? '' : MONTHS[startDate.month() - 1] + ' ' + startDate.year();
        String finish = (endDate == null) ? 'Present' : MONTHS[endDate.month() - 1] + ' ' + endDate.year();
        if (String.isBlank(start)) {
            return finish;
        }
        return start + ' - ' + finish;
    }
}