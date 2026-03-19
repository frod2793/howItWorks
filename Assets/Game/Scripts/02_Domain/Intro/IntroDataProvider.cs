using UnityEngine;
using System.IO;

#region 내부 로직
/// <summary>
/// [설명]: JSON 파일로부터 인트로 데이터를 불러오는 데이터 제공자 클래스입니다.
/// </summary>
public class IntroDataProvider
{
    private const string DEFAULT_PATH = "Data/IntroStory";

    /// <summary>
    /// [설명]: Resources 폴더에서 지정된 경로의 JSON 파일을 불러와 DTO로 변환합니다.
    /// </summary>
    /// <param name="path">JSON 파일의 Resources 상대 경로</param>
    /// <returns>파싱된 인트로 데이터 DTO</returns>
    public IntroStoryDataDTO LoadIntroData(string path = DEFAULT_PATH)
    {
        var jsonAsset = Resources.Load<TextAsset>(path);
        if (jsonAsset == null)
        {
            Debug.LogError($"[IntroDataProvider] JSON 파일을 찾을 수 없습니다: {path}");
            return new IntroStoryDataDTO();
        }

        try
        {
            var data = JsonUtility.FromJson<IntroStoryDataDTO>(jsonAsset.text);
            return data ?? new IntroStoryDataDTO();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[IntroDataProvider] JSON 파싱 중 오류 발생: {e.Message}");
            return new IntroStoryDataDTO();
        }
    }
}
#endregion
