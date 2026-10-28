mock_provider "google" {
  override_resource {
    target = google_compute_global_address.gateway
    values = {
      address = "34.95.10.20"
    }
  }
}

variables {
  project_id = "solidarytech-test"
  name       = "solidarytech"
}

run "hostname_sslip_a_partir_do_ip" {
  command = apply

  assert {
    condition     = output.hostname == "34-95-10-20.sslip.io"
    error_message = "O hostname deve ser o IP com hífens em sslip.io."
  }
  assert {
    condition     = google_certificate_manager_certificate.gateway.managed[0].domains == tolist(["34-95-10-20.sslip.io"])
    error_message = "O certificado gerenciado deve cobrir o hostname do Gateway."
  }
  assert {
    condition     = google_certificate_manager_certificate_map_entry.gateway.hostname == "34-95-10-20.sslip.io"
    error_message = "A entrada do mapa precisa apontar para o hostname."
  }
  assert {
    condition     = output.certificate_map == "solidarytech-gateway-certmap"
    error_message = "Nome do mapa usado na anotação networking.gke.io/certmap do Gateway."
  }
}

run "dominio_proprio_substitui_o_sslip" {
  command = apply

  variables {
    hostname = "doacoes.exemplo.org"
  }

  assert {
    condition     = output.hostname == "doacoes.exemplo.org"
    error_message = "Com domínio próprio, o hostname é o domínio."
  }
}
