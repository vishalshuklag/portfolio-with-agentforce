/**
 * Backing logic for the Personal Portfolio Agent's resume retrieval.
 * Returns the owner's resume content stored in the Resume_Details__c rich-text
 * field on active Portfolio_Item__c records (typically Type = Resume), as plain
 * text. The agent's LLM uses this content to answer visitor questions about
 * experience, skills, education, and certifications.
 *
 * This replaces the earlier Einstein Search retriever based approach so the
 * action works without depending on an external search index / data library.
 */
public with sharing class ResumeDetailsProvider {

    private static final Integer MAX_CONTENT_LENGTH = 30000;

    public class Request {
        @InvocableVariable(
            label='Search Keyword'
            description='The visitor question or key terms used to focus the answer on the relevant resume details.'
        )
        public String searchKeyword;
    }

    public class Result {
        @InvocableVariable(
            label='Resume Details'
            description='The owner resume content as readable text'
        )
        public String resumeDetails;
        @InvocableVariable(
            label='Has Data'
            description='True when resume content was found'
        )
        public Boolean hasData;
    }

    @InvocableMethod(
        label='Get Resume Details'
        description='Returns the owner full resume content as text for answering experience, skills, education, and certification questions'
    )
    public static List<Result> getResumeDetails(List<Request> requests) {
        List<Portfolio_Item__c> items = [
            SELECT Name, Type__c, Resume_Details__c
            FROM Portfolio_Item__c
            WHERE Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC
            LIMIT 200
        ];

        String combined = buildText(items);

        List<Result> results = new List<Result>();
        Integer iterations = (requests == null || requests.isEmpty()) ? 1 : requests.size();
        for (Integer i = 0; i < iterations; i++) {
            Result res = new Result();
            res.resumeDetails = combined;
            res.hasData = String.isNotBlank(combined);
            results.add(res);
        }
        return results;
    }

    private static String buildText(List<Portfolio_Item__c> items) {
        List<String> sections = new List<String>();
        for (Portfolio_Item__c item : items) {
            String text = htmlToText(item.Resume_Details__c);
            if (String.isNotBlank(text)) {
                String header = String.isBlank(item.Name) ? '' : (item.Name + ':\n');
                sections.add(header + text);
            }
        }
        if (sections.isEmpty()) {
            return null;
        }
        String combined = String.join(sections, '\n\n');
        if (combined.length() > MAX_CONTENT_LENGTH) {
            combined = combined.substring(0, MAX_CONTENT_LENGTH) + '...';
        }
        return combined;
    }

    private static String htmlToText(String html) {
        if (String.isBlank(html)) {
            return null;
        }
        String text = html;
        text = text.replaceAll('(?is)<script.*?</script>', ' ');
        text = text.replaceAll('(?is)<style.*?</style>', ' ');
        text = text.replaceAll('(?i)<br\\s*/?>', '\n');
        text = text.replaceAll('(?i)</(p|div|li|h1|h2|h3|h4|h5|h6|tr)>', '\n');
        text = text.replaceAll('<[^>]+>', ' ');
        text = text.replace('&nbsp;', ' ')
                   .replace('\u00A0', ' ')
                   .replace('&amp;', '&')
                   .replace('&lt;', '<')
                   .replace('&gt;', '>')
                   .replace('&quot;', '"')
                   .replace('&#39;', '\'');
        text = decodeNumericEntities(text);
        text = text.replaceAll('[ \\t\\x0B\\f\\r]+', ' ');
        text = text.replaceAll('\\n\\s*\\n+', '\n');
        return text.trim();
    }

    private static String decodeNumericEntities(String text) {
        if (String.isBlank(text) || !text.contains('&#')) {
            return text;
        }
        Matcher m = Pattern.compile('&#(\\d{1,6});').matcher(text);
        String result = '';
        Integer last = 0;
        while (m.find()) {
            result += text.substring(last, m.start());
            try {
                Integer codePoint = Integer.valueOf(m.group(1));
                result += String.fromCharArray(new List<Integer>{ codePoint });
            } catch (Exception e) {
                result += m.group(0);
            }
            last = m.end();
        }
        result += text.substring(last);
        return result;
    }
}