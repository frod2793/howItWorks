using System;
using System.Collections.Generic;

#region 데이터 모델 (DTO)
/// <summary>
/// [설명]: JSON에 정의된 개별 팝업 정보를 담는 DTO 클래스입니다.
/// </summary>
[Serializable]
public class PopupEntryDTO
{
    public string Key;
    public string Message;
    public string Subtitle;
    public string AnimationKey;
}

/// <summary>
/// [설명]: 전체 팝업 데이터 리스트를 담는 컨테이너 DTO입니다.
/// </summary>
[Serializable]
public class PopupDataDTO
{
    public List<PopupEntryDTO> Popups = new List<PopupEntryDTO>();
}
#endregion
