using System;
using System.Collections.Generic;

#region 데이터 모델 (DTO)
/// <summary>
/// [설명]: 인트로의 각 단계별 스토리 데이터를 담는 전송 객체입니다.
/// </summary>
[Serializable]
public class IntroStepDTO
{
    /// <summary>
    /// [설명]: 단계 번호입니다.
    /// </summary>
    public int Id;

    /// <summary>
    /// [설명]: 발화자 또는 상황 이름입니다.
    /// </summary>
    public string Speaker;

    /// <summary>
    /// [설명]: 출력될 텍스트 내용입니다.
    /// </summary>
    public string Content;
}

/// <summary>
/// [설명]: 전체 인트로 스토리 리스트를 관리하는 컨테이너 클래스입니다.
/// </summary>
[Serializable]
public class IntroStoryDataDTO
{
    public List<IntroStepDTO> Steps = new List<IntroStepDTO>();
}
#endregion
