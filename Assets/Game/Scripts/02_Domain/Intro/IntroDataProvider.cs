using UnityEngine;
using System.IO;
using System.Collections.Generic;

#region 내부 로직
/// <summary>
/// [설명]: StreamingAssets의 CSV 파일로부터 인트로 데이터를 불러오는 데이터 제공자 클래스입니다.
/// </summary>
public class IntroDataProvider
{
    private static readonly string DEFAULT_PATH = Path.Combine(Application.streamingAssetsPath, "Data/IntroStory.csv");

    /// <summary>
    /// [설명]: StreamingAssets 폴더에서 CSV 파일을 불러와 DTO로 변환합니다.
    /// </summary>
    /// <param name="path">CSV 파일의 절대 경로 (기본값: StreamingAssets/Data/IntroStory.csv)</param>
    /// <returns>파싱된 인트로 데이터 DTO</returns>
    public IntroStoryDataDTO LoadIntroData(string path = null)
    {
        string fullPath = string.IsNullOrEmpty(path) ? DEFAULT_PATH : path;

        if (!File.Exists(fullPath))
        {
            Debug.LogError($"[IntroDataProvider] CSV 파일을 찾을 수 없습니다: {fullPath}");
            return new IntroStoryDataDTO();
        }

        try
        {
            string csvText = File.ReadAllText(fullPath);
            var rows = CSVParser.Parse(csvText);
            
            if (rows.Count == 0) return new IntroStoryDataDTO();

            var data = new IntroStoryDataDTO();
            int startIndex = 0;

            // 1. 메타 데이터 파싱 (TypingSpeed)
            // 형식: TypingSpeed,0.05
            if (rows[0].Length >= 2 && rows[0][0].Trim() == "TypingSpeed")
            {
                if (float.TryParse(rows[0][1], out float speed))
                {
                    data.TypingSpeed = speed;
                }
                startIndex = 1;
            }

            // 2. 헤더 스킵 (Id,Speaker,Content)
            // 메타 데이터 다음 행이 헤더인지 확인
            if (rows.Count > startIndex && rows[startIndex].Length >= 3 && rows[startIndex][0].Trim() == "Id")
            {
                startIndex++;
            }

            // 3. 데이터 파싱
            for (int i = startIndex; i < rows.Count; i++)
            {
                var row = rows[i];
                // 빈 줄이거나 컬럼이 부족한 경우 건너뜀
                if (row.Length < 3 || string.IsNullOrWhiteSpace(row[0])) continue;

                if (int.TryParse(row[0].Trim(), out int id))
                {
                    data.Steps.Add(new IntroStepDTO
                    {
                        Id = id,
                        Speaker = row[1].Trim(),
                        Content = row[2].Trim()
                    });
                }
            }

            return data;
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[IntroDataProvider] CSV 로딩 중 오류 발생: {e.Message}");
            return new IntroStoryDataDTO();
        }
    }
}
#endregion
