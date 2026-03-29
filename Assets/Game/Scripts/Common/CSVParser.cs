using System.Collections.Generic;
using System.Text;

#region 유틸리티 로직
/// <summary>
/// [설명]: CSV 문자열을 파싱하여 리스트 형태로 변환하는 유틸리티 클래스입니다.
/// 큰따옴표(") 내부의 쉼표와 줄바꿈을 지원합니다.
/// </summary>
public static class CSVParser
{
    /// <summary>
    /// [설명]: CSV 전체 텍스트를 파싱하여 각 행(Row)의 필드 배열 리스트를 반환합니다.
    /// </summary>
    /// <param name="csvText">CSV 전체 문자열</param>
    /// <returns>파싱된 행들의 리스트</returns>
    public static List<string[]> Parse(string csvText)
    {
        var result = new List<string[]>();
        if (string.IsNullOrEmpty(csvText)) return result;

        var currentRow = new List<string>();
        var currentField = new StringBuilder();
        bool inQuotes = false;

        for (int i = 0; i < csvText.Length; i++)
        {
            char c = csvText[i];

            if (inQuotes)
            {
                if (c == '"')
                {
                    // 이중 큰따옴표("")는 하나의 큰따옴표로 처리
                    if (i + 1 < csvText.Length && csvText[i + 1] == '"')
                    {
                        currentField.Append('"');
                        i++;
                    }
                    else
                    {
                        inQuotes = false;
                    }
                }
                else
                {
                    currentField.Append(c);
                }
            }
            else
            {
                if (c == '"')
                {
                    inQuotes = true;
                }
                else if (c == ',')
                {
                    currentRow.Add(currentField.ToString());
                    currentField.Clear();
                }
                else if (c == '\n' || c == '\r')
                {
                    // 줄바꿈 처리 (\r\n 대응)
                    if (c == '\r' && i + 1 < csvText.Length && csvText[i + 1] == '\n')
                    {
                        i++;
                    }
                    
                    currentRow.Add(currentField.ToString());
                    result.Add(currentRow.ToArray());
                    currentRow.Clear();
                    currentField.Clear();
                }
                else
                {
                    currentField.Append(c);
                }
            }
        }

        // 마지막 행 처리
        if (currentRow.Count > 0 || currentField.Length > 0)
        {
            currentRow.Add(currentField.ToString());
            result.Add(currentRow.ToArray());
        }

        return result;
    }
}
#endregion
