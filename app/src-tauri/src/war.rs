//! The Galactic War status shown on Home, read from the official Helldivers 1 API: the same request
//! the game makes, answered with a couple of kilobytes of JSON.
//!
//! The API serves a self-signed certificate (the game trusts that one certificate), so a normal TLS
//! check refuses it. The connection here trusts that exact certificate and nothing else.

use std::sync::Arc;
use std::time::Duration;

use reqwest::header::CONTENT_TYPE;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{CryptoProvider, verify_tls12_signature, verify_tls13_signature};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{CertificateError, DigitallySignedStruct, SignatureScheme};
use sha2::{Digest, Sha256};

const URL: &str = "https://api.helldiversgame.com/1.0/";
/// SHA-256 of the API certificate (valid until August 2029).
const PIN: [u8; 32] = [
    0x3c, 0xc4, 0x32, 0xac, 0xc2, 0xde, 0x65, 0x2e, 0x11, 0xc9, 0xfb, 0x4a, 0x99, 0x14, 0x43, 0x2c, 0xc6, 0xcc, 0xc8, 0x4d, 0x20, 0xe7, 0xf0, 0x78,
    0x29, 0x49, 0x29, 0x18, 0x32, 0xb0, 0x77, 0x8b,
];

#[derive(Debug)]
struct Pinned(Arc<CryptoProvider>);

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(&self, cert: &CertificateDer<'_>, _: &[CertificateDer<'_>], _: &ServerName<'_>, _: &[u8], _: UnixTime) -> Result<ServerCertVerified, rustls::Error> {
        if Sha256::digest(cert.as_ref()).as_slice() == PIN {
            Ok(ServerCertVerified::assertion())
        } else {
            Err(rustls::Error::InvalidCertificate(CertificateError::UnknownIssuer))
        }
    }
    fn verify_tls12_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(message, cert, dss, &self.0.signature_verification_algorithms)
    }
    fn verify_tls13_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(message, cert, dss, &self.0.signature_verification_algorithms)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

fn client() -> Result<reqwest::Client, String> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let tls = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .map_err(|e| e.to_string())?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(Pinned(provider)))
        .with_no_client_auth();
    reqwest::Client::builder().tls_backend_preconfigured(tls).timeout(Duration::from_secs(15)).build().map_err(|e| e.to_string())
}

/// The campaign status as the API sends it (JSON text); the UI reads what it shows.
#[tauri::command]
pub async fn war_status() -> Result<String, String> {
    let res = client()?
        .post(URL)
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body("action=get_campaign_status")
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        return Err(format!("HTTP {}", res.status()));
    }
    res.text().await.map_err(|e| e.to_string())
}
