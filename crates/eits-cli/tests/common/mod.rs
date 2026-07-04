use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;

pub struct MockServer {
    pub url: String,
    handle: Option<std::thread::JoinHandle<Vec<Request>>>,
}
// method/path/body aren't asserted on by every test that uses this harness,
// only by the ones that need them.
#[allow(dead_code)]
pub struct Request {
    pub method: String,
    pub path: String,
    pub headers: Vec<(String, String)>,
    pub body: String,
}

/// Serve `responses` (status, body) in order, one per connection, then stop.
pub fn serve(responses: Vec<(u16, &'static str)>) -> MockServer {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/api/v1", listener.local_addr().unwrap());
    let handle = std::thread::spawn(move || {
        let mut seen = Vec::new();
        for (status, body) in responses {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            let mut parts = line.split_whitespace();
            let method = parts.next().unwrap_or("").to_string();
            let path = parts.next().unwrap_or("").to_string();
            let mut headers = Vec::new();
            let mut content_len = 0usize;
            loop {
                let mut h = String::new();
                reader.read_line(&mut h).unwrap();
                let h = h.trim_end().to_string();
                if h.is_empty() {
                    break;
                }
                if let Some((k, v)) = h.split_once(": ") {
                    if k.eq_ignore_ascii_case("content-length") {
                        content_len = v.parse().unwrap_or(0);
                    }
                    headers.push((k.to_lowercase(), v.to_string()));
                }
            }
            let mut body_buf = vec![0u8; content_len];
            reader.read_exact(&mut body_buf).unwrap();
            seen.push(Request {
                method,
                path,
                headers,
                body: String::from_utf8_lossy(&body_buf).into(),
            });
            let resp = format!(
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            stream.write_all(resp.as_bytes()).unwrap();
        }
        seen
    });
    MockServer {
        url,
        handle: Some(handle),
    }
}

impl MockServer {
    pub fn finish(mut self) -> Vec<Request> {
        self.handle.take().unwrap().join().unwrap()
    }
}
