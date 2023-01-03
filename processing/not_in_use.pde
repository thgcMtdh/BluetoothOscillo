// Split request string into method, resource, and body.
// Expected output hashmap is:
// {
//   method: "PUT",            // HTTP method
//   resource: "/cars/0/adc",  // resource URI
//   body: "{"seqNums": [0,1,2,3,4], "values": [0,1,4,9,16]}"
// }
HashMap<String,String> readRequest(String request) {
  HashMap<String, String> retval = new HashMap();
  int bodyStart = request.indexOf("{");
  if (request.startsWith("PUT")) {
    retval.put("method", "PUT");
    retval.put("resource", request.substring(4, bodyStart - 1));
    retval.put("body", request.substring(bodyStart));
    
  } else if (request.startsWith("GET")) {
    retval.put("method", "GET");
    retval.put("resource", request.substring(4, bodyStart - 1));
    retval.put("body", request.substring(bodyStart));
    
  } else {
    retval.put("method", "");
    retval.put("resource", "");
    retval.put("body", "");
  }
  return retval;
}
