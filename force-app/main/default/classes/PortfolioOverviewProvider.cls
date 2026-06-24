/**
 * Discovery action for the Personal Portfolio Agent.
 *
 * Returns the distinct categories (Type__c) that actually exist among the
 * owner's active Portfolio_Item__c records, with item counts and a few example
 * titles each, plus a ready-to-read summary string. The agent calls this to
 * learn exactly what the portfolio contains, so it can (a) tell visitors what
 * they can explore and (b) only ever offer categories that truly exist — never
 * inventing content types (YouTube, GitHub, Project, etc.) the owner has not
 * actually added. This is what keeps "what can I ask about?" grounded in data.
 */
public with sharing class PortfolioOverviewProvider {

    // The overview always reflects the full active portfolio. Invocable methods
    // require at least one @InvocableVariable on the request type, so we expose a
    // single optional hint that the agent can safely leave blank; it does not
    // change the result.
    public class Request {
        @InvocableVariable(
            label='Focus Area'
            description='Optional and usually left blank. The overview always returns every category in the portfolio regardless of this value.'
        )
        public String focusArea;
    }

    public class Category {
        @InvocableVariable(
            label='Item Type'
            description='A category that exists in the portfolio (e.g. Bio, Experience, Certification, Blog)'
        )
        public String itemType;
        @InvocableVariable(
            label='Count'
            description='How many active items exist in this category'
        )
        public Integer count;
        @InvocableVariable(
            label='Examples'
            description='Up to three example item titles in this category'
        )
        public String examples;
    }

    public class Result {
        @InvocableVariable(
            label='Categories'
            description='Distinct categories present in the portfolio with counts and example titles'
        )
        public List<Category> categories;
        @InvocableVariable(
            label='Summary'
            description='Human-readable summary of what the portfolio contains'
        )
        public String summary;
        @InvocableVariable(
            label='Has Data'
            description='True when the portfolio has at least one active item'
        )
        public Boolean hasData;
    }

    // Preferred display order so the menu reads naturally. Any custom types the
    // owner has added that are not in this list are appended alphabetically.
    private static final List<String> PREFERRED_ORDER = new List<String>{
        'Bio', 'Now', 'Experience', 'Education', 'Skill', 'AI Tool', 'Certification',
        'Award', 'Project', 'Service', 'Endorsement', 'Community', 'Volunteering',
        'Blog', 'Publication', 'White Paper', 'Talk', 'YouTube', 'GitHub', 'LinkedIn',
        'Website', 'Language', 'Interest', 'Other', 'Resume'
    };

    @InvocableMethod(
        label='Get Portfolio Overview'
        description='Lists the categories that actually exist in the owner portfolio with counts and examples, so the agent knows exactly what it can talk about'
    )
    public static List<Result> getOverview(List<Request> requests) {
        Map<String, Integer> countByType = new Map<String, Integer>();
        Map<String, List<String>> examplesByType = new Map<String, List<String>>();
        for (Portfolio_Item__c rec : [
            SELECT Name, Type__c
            FROM Portfolio_Item__c
            WHERE Active__c = true AND Type__c != null
            ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC
            LIMIT 500
        ]) {
            Integer current = countByType.containsKey(rec.Type__c) ? countByType.get(rec.Type__c) : 0;
            countByType.put(rec.Type__c, current + 1);
            List<String> titles = examplesByType.get(rec.Type__c);
            if (titles == null) {
                titles = new List<String>();
                examplesByType.put(rec.Type__c, titles);
            }
            if (titles.size() < 3 && String.isNotBlank(rec.Name)) {
                titles.add(rec.Name);
            }
        }

        List<String> orderedTypes = orderTypes(countByType.keySet());

        List<Category> categories = new List<Category>();
        List<String> summaryLines = new List<String>();
        for (String type : orderedTypes) {
            Integer cnt = countByType.get(type);
            Category cat = new Category();
            cat.itemType = type;
            cat.count = cnt;
            List<String> titles = examplesByType.get(type);
            cat.examples = (titles == null) ? null : String.join(titles, ', ');
            categories.add(cat);
            summaryLines.add('- ' + type + ' (' + cnt + (cnt == 1 ? ' item)' : ' items)'));
        }

        Result res = new Result();
        res.categories = categories;
        res.hasData = !categories.isEmpty();
        res.summary = categories.isEmpty()
            ? 'The portfolio has no items yet.'
            : String.join(summaryLines, '\n');

        Integer iterations = (requests == null || requests.isEmpty()) ? 1 : requests.size();
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < iterations; i++) {
            results.add(res);
        }
        return results;
    }

    private static List<String> orderTypes(Set<String> presentTypes) {
        Map<String, String> actualByLower = new Map<String, String>();
        for (String t : presentTypes) {
            actualByLower.put(t.toLowerCase(), t);
        }
        List<String> ordered = new List<String>();
        Set<String> usedLower = new Set<String>();
        for (String preferred : PREFERRED_ORDER) {
            String lower = preferred.toLowerCase();
            if (actualByLower.containsKey(lower)) {
                ordered.add(actualByLower.get(lower));
                usedLower.add(lower);
            }
        }
        List<String> leftovers = new List<String>();
        for (String t : presentTypes) {
            if (!usedLower.contains(t.toLowerCase())) {
                leftovers.add(t);
            }
        }
        leftovers.sort();
        ordered.addAll(leftovers);
        return ordered;
    }
}