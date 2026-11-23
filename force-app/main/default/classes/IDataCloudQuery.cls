/**
 * Small interface around the Data Cloud Query API.
 * Lets unit tests swap in a fake, because ConnectApi Data Cloud calls
 * cannot return real data inside Apex tests.
 *
 * Each row is returned as a map of lower-case column name -> value.
 */
public interface IDataCloudQuery {
    List<Map<String, Object>> query(String sql);
}
