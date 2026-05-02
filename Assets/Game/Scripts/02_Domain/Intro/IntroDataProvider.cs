using UnityEngine;
using System.IO;
using System.Collections.Generic;

public class IntroDataProvider
{
    private static readonly string DEFAULT_PATH = Path.Combine(Application.streamingAssetsPath, "Data/IntroStory.csv");

    public IntroStoryDataDTO LoadIntroData(string path = null)
    {
        string fullPath = string.IsNullOrEmpty(path) ? DEFAULT_PATH : path;

        if (!File.Exists(fullPath))
        {
            Debug.LogError($"[IntroDataProvider] 파일 없음: {fullPath}");
            return new IntroStoryDataDTO();
        }

        try
        {
            string csvText = File.ReadAllText(fullPath);
            var rows = CSVParser.Parse(csvText);
            
            if (rows.Count == 0)
            {
                return new IntroStoryDataDTO();
            }

            var data = new IntroStoryDataDTO();
            int startIndex = 0;

            if (rows[0].Length >= 2 && rows[0][0].Trim() == "TypingSpeed")
            {
                if (float.TryParse(rows[0][1], out float speed))
                {
                    data.TypingSpeed = speed;
                }
                startIndex = 1;
            }

            if (rows.Count > startIndex && rows[startIndex].Length >= 3 && rows[startIndex][0].Trim() == "Id")
            {
                startIndex++;
            }

            for (int i = startIndex; i < rows.Count; i++)
            {
                var row = rows[i];
                if (row.Length < 3 || string.IsNullOrWhiteSpace(row[0]))
                {
                    continue;
                }

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
            Debug.LogError($"[IntroDataProvider] 로드 실패: {e.Message}");
            return new IntroStoryDataDTO();
        }
    }
}
