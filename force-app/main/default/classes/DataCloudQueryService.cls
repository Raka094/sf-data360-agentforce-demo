/**
 * Real implementation of IDataCloudQuery.
 * Runs ANSI SQL against Data Cloud with ConnectApi.CdpQuery.queryAnsiSqlV2
 * and follows nextBatchId until all rows are read.
 */
public with sharing class DataCloudQueryService implements IDataCloudQuery {

    private static final Integer MAX_BATCHES = 20; // safety stop

    public List<Map<String, Object>> query(String sql) {
        ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
        input.sql = sql;
        ConnectApi.CdpQueryOutputV2 output = ConnectApi.CdpQuery.queryAnsiSqlV2(input);

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        if (output == null) {
            return rows;
        }

        // Column positions only come with the first batch
        Map<String, Integer> positions = new Map<String, Integer>();
        if (output.metadata != null) {
            for (String col : output.metadata.keySet()) {
                positions.put(col, output.metadata.get(col).placeInOrder);
            }
        }

        Integer batches = 0;
        while (output != null && batches < MAX_BATCHES) {
            List<List<Object>> raw = new List<List<Object>>();
            if (output.data != null) {
                for (ConnectApi.CdpQueryV2Row r : output.data) {
                    raw.add(r.rowData);
                }
            }
            rows.addAll(toMaps(positions, raw));
            batches++;
            if (String.isBlank(output.nextBatchId)) {
                break;
            }
            output = ConnectApi.CdpQuery.nextBatchAnsiSqlV2(output.nextBatchId);
        }
        return rows;
    }

    /**
     * Turns positional rows into maps keyed by lower-case column name.
     * Kept public + static so it can be unit tested without Data Cloud.
     */
    public static List<Map<String, Object>> toMaps(Map<String, Integer> positions, List<List<Object>> rawRows) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (rawRows == null) {
            return result;
        }
        for (List<Object> raw : rawRows) {
            Map<String, Object> row = new Map<String, Object>();
            for (String col : positions.keySet()) {
                Integer i = positions.get(col);
                if (raw != null && i != null && i >= 0 && i < raw.size()) {
                    row.put(col.toLowerCase(), raw[i]);
                }
            }
            result.add(row);
        }
        return result;
    }
}
