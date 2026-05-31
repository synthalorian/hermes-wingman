use axum::{extract::Request, http::StatusCode, middleware::Next, response::Response};
use std::time::Instant;

pub async fn log_requests(req: Request, next: Next) -> Result<Response, StatusCode> {
    let start = Instant::now();
    let method = req.method().clone();
    let uri = req.uri().clone();

    let response = next.run(req).await;

    let duration = start.elapsed();
    let _status = response.status();
    println!("[{}] {} {} — {:?}", chrono::Local::now().format("%Y-%m-%d %H:%M:%S"), method, uri, duration);

    Ok(response)
}
