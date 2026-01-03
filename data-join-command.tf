# Control Plane 노드에서 join command를 자동으로 가져오는 external data source
# terraform apply 실행 시 자동으로 최신 join command를 생성
# var.k8s_join_command가 비어있을 때만 사용됨

data "external" "k8s_join_command" {
  program = ["bash", "${path.module}/scripts/get-join-command.sh"]

  query = {
    ssh_host         = var.k8s_control_plane_ssh_host
    ssh_user         = var.k8s_control_plane_ssh_user
    ssh_key_path     = var.k8s_control_plane_ssh_key != "" ? var.k8s_control_plane_ssh_key : ""
    api_server_domain = var.k8s_api_server_domain != "" ? var.k8s_api_server_domain : "main-node.me"
  }
}

# Local 값으로 join command 저장 (IP 치환 완료된 버전)
locals {
  # var.k8s_join_command가 비어있으면 external data source에서 가져온 값 사용
  # 그렇지 않으면 기존 변수 사용 (하위 호환성)
  # try()를 사용하여 external data source가 실패해도 에러 없이 처리
  k8s_join_command = var.k8s_join_command != "" ? var.k8s_join_command : try(data.external.k8s_join_command.result.join_command, "")
}

